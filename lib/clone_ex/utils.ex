defmodule CloneEx.Utils do
  @moduledoc """
  Shared utility functions used across CloneEx modules.
  """

  @spec dir_size(Path.t()) :: non_neg_integer()
  def dir_size(path) do
    case System.cmd("du", ["-sk", path], stderr_to_stdout: true) do
      {output, 0} ->
        [kb | _] = String.split(output, "\t")
        String.to_integer(kb) * 1024
    end
  end
end
