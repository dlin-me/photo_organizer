defmodule PhotoOrganizer.CLI do
  @moduledoc """
  The command-line interface for the photo organizer application.
  """

  def main(args) do
    case parse_args(args) do
      {:ok, :import, source, target} ->
        PhotoOrganizer.Organizer.import(source, target)

      {:ok, :index, target} ->
        PhotoOrganizer.Organizer.index(target)

      {:ok, :report, target} ->
        PhotoOrganizer.Organizer.report(target)

      :error ->
        usage()
    end
  end

  defp parse_args(["import", source | rest]) do
    target =
      case rest do
        [target] -> target
        _ -> "."
      end

    {:ok, :import, source, target}
  end

  defp parse_args(["index" | rest]) do
    target =
      case rest do
        [target] -> target
        _ -> "."
      end

    {:ok, :index, target}
  end

  defp parse_args(["report" | rest]) do
    target =
      case rest do
        [target] -> target
        _ -> "."
      end

    {:ok, :report, target}
  end

  defp parse_args(_), do: :error

  defp usage do
    IO.puts("""
    Usage:
      po import SOURCE_DIR [TARGET_DIR]
      po index [TARGET_DIR]
      po report [TARGET_DIR]

    Commands:
      import    Import photos and videos from SOURCE_DIR to TARGET_DIR (default: current directory)
      index     Rebuild the database index for media files in TARGET_DIR (default: current directory)
      report    Report the total number of files in the database in TARGET_DIR (default: current directory)
    """)
  end
end
