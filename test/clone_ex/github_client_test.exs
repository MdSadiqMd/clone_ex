defmodule CloneEx.GitHubClientTest do
  use ExUnit.Case
  alias CloneEx.GitHubClient

  # Setup Tesla mock for all tests in this module
  setup do
    Tesla.Mock.mock_global(fn
      %{url: "https://api.github.com/users/singlepage/repos"} ->
        %Tesla.Env{
          status: 200,
          body: [
            %{
              "name" => "repo1",
              "full_name" => "singlepage/repo1",
              "clone_url" => "https://github.com/singlepage/repo1.git",
              "size" => 1024,
              "stargazers_count" => 10,
              "private" => false,
              "fork" => false,
              "default_branch" => "main"
            }
          ],
          headers: [
            {"x-ratelimit-remaining", "4999"},
            {"x-ratelimit-reset", "1234567890"}
          ]
        }

      %{url: "https://api.github.com/users/multipage/repos", query: [per_page: 100, page: 1]} ->
        %Tesla.Env{
          status: 200,
          body: [
            %{
              "name" => "repo1",
              "full_name" => "multipage/repo1",
              "clone_url" => "https://github.com/multipage/repo1.git",
              "size" => 1024,
              "stargazers_count" => 10,
              "private" => false,
              "fork" => false,
              "default_branch" => "main"
            }
          ],
          headers: [
            {"link",
             ~s(<https://api.github.com/users/multipage/repos?page=2>; rel="next", <https://api.github.com/users/multipage/repos?page=2>; rel="last")},
            {"x-ratelimit-remaining", "4999"},
            {"x-ratelimit-reset", "1234567890"}
          ]
        }

      %{url: "https://api.github.com/users/multipage/repos", query: [per_page: 100, page: 2]} ->
        %Tesla.Env{
          status: 200,
          body: [
            %{
              "name" => "repo2",
              "full_name" => "multipage/repo2",
              "clone_url" => "https://github.com/multipage/repo2.git",
              "size" => 2048,
              "stargazers_count" => 20,
              "private" => false,
              "fork" => false,
              "default_branch" => "main"
            }
          ],
          headers: [
            {"x-ratelimit-remaining", "4999"},
            {"x-ratelimit-reset", "1234567890"}
          ]
        }

      %{url: "https://api.github.com/users/notfound/repos"} ->
        %Tesla.Env{status: 404}

      %{url: "https://api.github.com/users/unauth/repos"} ->
        %Tesla.Env{status: 401}

      %{url: "https://api.github.com/users/ratelimited/repos"} ->
        %Tesla.Env{status: 403, body: %{"message" => "API rate limit exceeded"}}
    end)

    :ok
  end

  describe "list_repos/2" do
    test "fetches single page successfully" do
      assert {:ok, repos} = GitHubClient.list_repos("singlepage", adapter: Tesla.Mock)
      assert length(repos) == 1
      assert hd(repos).name == "repo1"
    end

    test "handles pagination correctly" do
      assert {:ok, repos} = GitHubClient.list_repos("multipage", adapter: Tesla.Mock)
      assert length(repos) == 2
      names = Enum.map(repos, & &1.name)
      assert "repo1" in names
      assert "repo2" in names
    end

    test "handles 404 not found" do
      assert {:error, :not_found} = GitHubClient.list_repos("notfound", adapter: Tesla.Mock)
    end

    test "handles 401 unauthorized" do
      assert {:error, :unauthorized} = GitHubClient.list_repos("unauth", adapter: Tesla.Mock)
    end

    test "handles 403 rate limited" do
      assert {:error, :rate_limited} = GitHubClient.list_repos("ratelimited", adapter: Tesla.Mock)
    end

    test "repo map has all expected keys" do
      {:ok, [repo | _]} = GitHubClient.list_repos("singlepage", adapter: Tesla.Mock)

      assert Map.has_key?(repo, :name)
      assert Map.has_key?(repo, :full_name)
      assert Map.has_key?(repo, :clone_url)
      assert Map.has_key?(repo, :size_kb)
      assert Map.has_key?(repo, :stargazers_count)
      assert Map.has_key?(repo, :private)
      assert Map.has_key?(repo, :fork)
      assert Map.has_key?(repo, :default_branch)
    end
  end

  describe "parse_link_header/1" do
    test "parses valid link header with multiple rels" do
      header =
        ~s(<https://api.github.com/user/repos?page=2>; rel="next", <https://api.github.com/user/repos?page=5>; rel="last")

      expected = %{
        "next" => "https://api.github.com/user/repos?page=2",
        "last" => "https://api.github.com/user/repos?page=5"
      }

      assert GitHubClient.parse_link_header(header) == expected
    end

    test "parses single rel" do
      header = ~s(<https://api.github.com/user/repos?page=3>; rel="next")

      assert GitHubClient.parse_link_header(header) == %{
               "next" => "https://api.github.com/user/repos?page=3"
             }
    end

    test "handles nil" do
      assert GitHubClient.parse_link_header(nil) == %{}
    end

    test "handles empty string" do
      assert GitHubClient.parse_link_header("") == %{}
    end

    test "handles malformed header without crashing" do
      assert GitHubClient.parse_link_header("not a real link header") == %{}
    end
  end

  describe "new/1" do
    test "creates client without token" do
      client = GitHubClient.new()
      assert %Tesla.Client{} = client
    end

    test "creates client with token" do
      client = GitHubClient.new(token: "ghp_test123")
      assert %Tesla.Client{} = client
      # BearerAuth middleware should be first
      assert {Tesla.Middleware.BearerAuth, :call, _} = hd(client.pre)
    end

    test "creates client with custom adapter" do
      client = GitHubClient.new(adapter: Tesla.Mock)
      assert %Tesla.Client{} = client
    end
  end
end
