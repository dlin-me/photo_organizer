defmodule PhotoOrganizer.FileScanner do
  @moduledoc """
  Scans a directory recursively for media files (images and videos).
  """

  # Define the file extensions that you consider as images and videos.
  @image_extensions ~w(.jpg .jpeg .png .gif .bmp .tif .tiff)
  @video_extensions ~w(.mp4 .mov .avi .mkv .heic .vob .mpg .wmv)

  @doc """
  Scans the given `path` recursively and returns a list of media file paths.
  """
  def scan_media_files(path) when is_binary(path) do
    scan_media_files(path, [])
  end

  # Private recursive function that accumulates media file paths.
  defp scan_media_files(current_path, acc) do
    case File.ls(current_path) do
      {:ok, entries} ->
        Enum.reduce(entries, acc, fn entry, acc ->
          full_path = Path.join(current_path, entry)

          cond do
            File.dir?(full_path) ->
              # Recurse into directories.
              scan_media_files(full_path, acc)

            File.regular?(full_path) and media_file?(full_path) and not ignored_file?(entry) ->
              # Accumulate the media file.
              [full_path | acc]

            true ->
              # Skip any other type of file.
              acc
          end
        end)

      {:error, reason} ->
        IO.warn("Could not list directory #{current_path}: #{reason}")
        acc
    end
  end

  # Determines if a file is a media file by checking its extension.
  defp media_file?(file) do
    ext = file |> Path.extname() |> String.downcase()
    ext in @image_extensions or ext in @video_extensions
  end

  # Determines if a file should be ignored (Apple Double files or files starting with '.').
  defp ignored_file?(file) do
    String.starts_with?(file, ".")
  end
end
