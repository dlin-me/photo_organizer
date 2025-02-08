defmodule PhotoOrganizer.Organizer do
  @moduledoc """
  Organizes photos and videos by copying them from a source directory to a target
  directory using a specific naming scheme, and records file info in a CubDB
  database (version 2.0.2) to avoid duplicates.

  If a file with the same file hash and file size already exists, the new file is
  moved to a duplicate location.
  """

  alias PhotoOrganizer.{FileScanner, Metadata}

  @db_name "cubdb"

  @doc """
  Imports photos and videos from a source directory to a target directory.

  - Extracts metadata for each file.
  - Builds a target file path and file name using the metadata.
  - Ensures the target directory exists.
  - Moves the file to the target location.

  ## Parameters

    - `source_dir`: The directory containing the media files to import.
    - `target_dir`: (Optional) The directory to import the media files into. Defaults to the current directory.
  """
  def import(source_dir, target_dir \\ ".") do
    # Start the CubDB instance with the data directory set under target_dir.
    db_dir = Path.join(target_dir, @db_name)

    # Ensure the database directory exists.
    File.mkdir_p!(db_dir)

    {:ok, db} = CubDB.start_link(data_dir: db_dir)

    media_files = FileScanner.scan_media_files(source_dir)
    total_files = length(media_files)
    IO.puts("Found #{total_files} media files.")

    Enum.with_index(media_files)
    |> Enum.each(fn {file, index} ->
      case move_and_rename(file, target_dir, db) do
        {:ok, message} ->
          # Calculate and display progress percentage.
          progress = div((index + 1) * 100, total_files)
          IO.write(IO.ANSI.cursor_left(1000) <> IO.ANSI.clear_line())
          IO.write("[#{progress}%] \t #{file}: #{message}")

        {:error, reason} ->
          IO.puts("Failed to import #{file}: #{inspect(reason)} \n")
      end
    end)

    # Optionally, shut down the DB when done.
    CubDB.stop(db)
  end

  @doc """
  Moves and renames the given file to the target directory.

  The new file path is constructed according to the naming pattern:

      <target_dir>/<photo|video>/YYYY/MM/DD_HH_MM_SS_[exif|mod]_[current timestamp in seconds].[ext]

  ## Parameters

    - `source`: The source file path.
    - `target_dir`: The target directory.
    - `db`: The CubDB instance.
  """
  def move_and_rename(source, target_dir, db) when is_binary(source) and is_binary(target_dir) do
    with {:ok, meta} <- Metadata.extract(source) do
      key = {meta.md5, meta.file_size}

      # Check if the file already exists in the database.
      is_duplication =
        case CubDB.get(db, key) do
          nil -> false
          _ -> true
        end

      target_prefix = if is_duplication, do: "duplication", else: ""
      target_path = build_target_file(source, meta, target_dir, target_prefix)
      target_subdir = Path.dirname(target_path)

      case File.mkdir_p(target_subdir) do
        :ok ->
          case File.rename(source, target_path) do
            :ok ->
              unless is_duplication do
                # Update the database with the new file record.
                CubDB.put(db, key, target_path)
              end

              message = if is_duplication, do: "Duplicated", else: "Imported"
              {:ok, message}

            {:error, :exdev} ->
              # Handle cross-device link error by copying and deleting.
              case File.cp(source, target_path) do
                :ok ->
                  File.rm(source)

                  unless is_duplication do
                    # Update the database with the new file record.
                    CubDB.put(db, key, target_path)
                  end

                  message = if is_duplication, do: "Duplicated", else: "Imported"
                  {:ok, message}

                {:error, reason} ->
                  {:error, reason}
              end

            {:error, reason} ->
              {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, reason} -> {:error, "#{reason} (file: #{source})"}
    end
  end

  @doc """
  Rebuilds the database index for media files in the target directory.

  ## Parameters

    - `target_dir`: (Optional) The directory containing the media files to index. Defaults to the current directory.
  """
  def index(target_dir \\ ".") do
    # Clear the existing database.
    db_dir = Path.join(target_dir, @db_name)
    File.rm_rf!(db_dir)
    File.mkdir_p!(db_dir)

    {:ok, db} = CubDB.start_link(data_dir: db_dir)

    # Scan media files in the 'photo' and 'video' subdirectories.
    photo_dir = Path.join(target_dir, "photo")
    video_dir = Path.join(target_dir, "video")

    photo_files =
      if File.exists?(photo_dir), do: FileScanner.scan_media_files(photo_dir), else: []

    video_files =
      if File.exists?(video_dir), do: FileScanner.scan_media_files(video_dir), else: []

    media_files = photo_files ++ video_files
    total_files = length(media_files)
    IO.puts("Found #{total_files} media files.")

    Enum.with_index(media_files)
    |> Enum.each(fn {file, index} ->
      case rebuild_db_record(file, db) do
        {:ok, message} ->
          # Calculate and display progress percentage.
          progress = div((index + 1) * 100, total_files)
          IO.write(IO.ANSI.cursor_left(1000) <> IO.ANSI.clear_line())
          IO.write("[#{progress}%] \t #{file}: #{message}")

        {:error, reason} ->
          IO.puts("Failed to index #{file}: #{inspect(reason)}")
      end
    end)

    # Optionally, shut down the DB when done.
    CubDB.stop(db)
  end

  @doc """
  Reports the total number of files in the database in the target directory.

  ## Parameters

    - `target_dir`: (Optional) The directory containing the database to report on. Defaults to the current directory.
  """
  def report(target_dir \\ ".") do
    db_dir = Path.join(target_dir, @db_name)

    if File.exists?(db_dir) do
      {:ok, db} = CubDB.start_link(data_dir: db_dir)

      total_files = CubDB.size(db)
      IO.puts("Total number of files: #{total_files}")

      # Optionally, shut down the DB when done.
      CubDB.stop(db)
    else
      IO.puts("Database not found in #{db_dir}")
    end
  end

  @doc false
  # Rebuilds the database record for a given file.
  defp rebuild_db_record(file, db) do
    with {:ok, meta} <- Metadata.extract(file) do
      key = {meta.md5, meta.file_size}

      # Update the database with the file record.
      CubDB.put(db, key, file)
      {:ok, "Indexed"}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  # Builds the target file path based on metadata.
  #
  # The final path (relative to target_dir) will be:
  #   <photo|video>/YYYY/MM/DD_HH_MM_SS_[exif|mod]_[current timestamp in seconds].[ext]
  defp build_target_file(source, meta, target_dir, prefix) do
    ext = Path.extname(source)
    type = meta.type

    # Parse meta.datetime which is expected to be in the format "YYYY:MM:DD HH:MM:SS".
    [date_str, time_str] = String.split(meta.datetime, " ")
    [year, month, day] = String.split(date_str, ":")
    [hour, minute, second] = String.split(time_str, ":")

    reliability = if meta.reliable, do: "exif", else: "mod"
    # Get the current timestamp in seconds.
    current_ts = :os.system_time(:second)

    # Build the subdirectory: <target_dir>/<photo|video>/YYYY/MM
    subdir = Path.join([target_dir, prefix, type, year, month])
    # Build the file name: DD_HH_MM_SS_[exif|mod]_[current timestamp in seconds].[ext]
    filename = "#{day}_#{hour}_#{minute}_#{second}_#{reliability}_#{current_ts}#{ext}"
    Path.join(subdir, filename)
  end
end
