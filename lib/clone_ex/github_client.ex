defmodule CloneEx.GitHubClient do
  @moduledoc """
  API client for fetching GitHub repositories.

  Handles pagination (concurrent when possible), rate limiting, and
  standardizing response payloads into consistent maps.
  """

  require Logger

  @version "0.1.0"

  @doc """
  Creates a new Tesla client with the standard middleware stack.
  """
  @spec new(keyword()) :: Tesla.Client.t()
  def new(opts \\ []) do
    base_middlewares = [
      {Tesla.Middleware.BaseUrl, "https://api.github.com"},
      {Tesla.Middleware.Headers,
       [
         {"accept", "application/vnd.github+json"},
         {"x-github-api-version", "2022-11-28"},
         {"user-agent", "CloneEx/#{@version} Elixir/#{System.version()}"}
       ]},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Retry,
       delay: 1_000,
       max_retries: 2,
       should_retry: fn
         {:ok, %{status: status}} when status in [500, 502, 503, 504] -> true
         {:error, _} -> true
         _ -> false
       end}
    ]

    middlewares =
      if token = opts[:token] do
        [{Tesla.Middleware.BearerAuth, token: token} | base_middlewares]
      else
        base_middlewares
      end

    if adapter = opts[:adapter] do
      Tesla.client(middlewares, adapter)
    else
      Tesla.client(middlewares)
    end
  end

  @doc """
  Fetches all repositories for a user, handling pagination automatically.

  After fetching the first page, if the `Link` header contains `rel="last"`,
  remaining pages are fetched concurrently using `Task.async_stream/3` for
  maximum throughput.
  """
  @spec list_repos(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_repos(username, opts \\ []) do
    client = new(opts)

    # Fetch page 1 to determine total pages
    case get_repos_page(client, username, 1) do
      {:ok, first_repos, headers} ->
        check_rate_limit(headers)
        link_header = get_header(headers, "link")
        links = parse_link_header(link_header)

        case extract_last_page(links) do
          nil ->
            # Single page — we're done
            {:ok, first_repos}

          last_page when last_page > 1 ->
            # Concurrent fetch of pages 2..last
            fetch_remaining_pages_concurrent(client, username, 2..last_page, first_repos)

          _ ->
            {:ok, first_repos}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Fetches pages 2..N concurrently and merges results with page 1 repos.
  # Uses Task.async_stream for bounded concurrency (max 4 concurrent requests
  # to stay well within GitHub's rate limits).
  @spec fetch_remaining_pages_concurrent(Tesla.Client.t(), String.t(), Range.t(), [map()]) ::
          {:ok, [map()]} | {:error, term()}
  defp fetch_remaining_pages_concurrent(client, username, page_range, first_page_repos) do
    results =
      page_range
      |> Task.async_stream(
        fn page -> get_repos_page(client, username, page) end,
        max_concurrency: 4,
        timeout: 30_000,
        ordered: true
      )
      |> Enum.reduce_while({:ok, [first_page_repos]}, fn
        {:ok, {:ok, repos, headers}}, {:ok, acc} ->
          check_rate_limit(headers)
          {:cont, {:ok, [repos | acc]}}

        {:ok, {:error, reason}}, _acc ->
          {:halt, {:error, reason}}

        {:exit, reason}, _acc ->
          {:halt, {:error, {:page_fetch_failed, reason}}}
      end)

    case results do
      {:ok, chunks} ->
        # Chunks are in reverse order (prepended), reverse and flatten
        {:ok, chunks |> Enum.reverse() |> List.flatten()}

      {:error, _} = error ->
        error
    end
  end

  @doc false
  @spec get_repos_page(Tesla.Client.t(), String.t(), pos_integer()) ::
          {:ok, [map()], [{String.t(), String.t()}]} | {:error, term()}
  def get_repos_page(client, username, page) do
    url = "/users/#{username}/repos"
    query = [per_page: 100, page: page]

    case Tesla.get(client, url, query: query) do
      {:ok, %Tesla.Env{status: 200, body: body, headers: headers}} when is_list(body) ->
        repos = Enum.map(body, &map_repo/1)
        {:ok, repos, headers}

      {:ok, %Tesla.Env{status: 200, body: _body, headers: headers}} ->
        # Defensive: body wasn't a list (unexpected API response)
        {:ok, [], headers}

      {:ok, %Tesla.Env{status: 404}} ->
        {:error, :not_found}

      {:ok, %Tesla.Env{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %Tesla.Env{status: 403, body: body}} ->
        if is_map(body) and String.contains?(body["message"] || "", "API rate limit") do
          {:error, :rate_limited}
        else
          {:error, {:forbidden, body}}
        end

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end

  defp map_repo(raw) when is_map(raw) do
    %{
      name: raw["name"],
      full_name: raw["full_name"],
      clone_url: raw["clone_url"],
      size_kb: raw["size"] || 0,
      stargazers_count: raw["stargazers_count"] || 0,
      private: raw["private"] || false,
      fork: raw["fork"] || false,
      default_branch: raw["default_branch"]
    }
  end

  @doc """
  Parses RFC 5988 Link header into a map of relation → URL.

  ## Example
      iex> CloneEx.GitHubClient.parse_link_header(~s(<https://api.github.com/user/repos?page=2>; rel="next"))
      %{"next" => "https://api.github.com/user/repos?page=2"}
  """
  @spec parse_link_header(String.t() | nil) :: map()
  def parse_link_header(nil), do: %{}
  def parse_link_header(""), do: %{}

  def parse_link_header(header) do
    header
    |> String.split(",")
    |> Enum.reduce(%{}, fn part, acc ->
      case Regex.run(~r/<([^>]+)>;\s*rel="([^"]+)"/, part) do
        [_, url, rel] -> Map.put(acc, rel, url)
        _ -> acc
      end
    end)
  end

  # Extracts the last page number from parsed Link header relations.
  @spec extract_last_page(map()) :: pos_integer() | nil
  defp extract_last_page(%{"last" => url}) do
    case Regex.run(~r/[?&]page=(\d+)/, url) do
      [_, page_str] -> String.to_integer(page_str)
      _ -> nil
    end
  end

  defp extract_last_page(_), do: nil

  defp get_header(headers, key) do
    Enum.find_value(headers, fn {k, v} ->
      if String.downcase(k) == key, do: v
    end)
  end

  defp check_rate_limit(headers) do
    remaining_str = get_header(headers, "x-ratelimit-remaining")
    reset_str = get_header(headers, "x-ratelimit-reset")

    if remaining_str && reset_str do
      remaining = String.to_integer(remaining_str)
      reset = String.to_integer(reset_str)

      if remaining < 5 do
        now = System.os_time(:second)
        wait_seconds = max(reset - now, 1)

        Logger.warning(
          "GitHub API rate limit nearly exhausted (#{remaining} remaining). Sleeping #{wait_seconds}s..."
        )

        Process.sleep((wait_seconds + 1) * 1000)
      end
    end
  end
end
