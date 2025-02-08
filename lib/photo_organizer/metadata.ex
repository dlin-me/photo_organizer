defmodule PhotoOrganizer.Metadata do
  @moduledoc """
  Extracts metadata from media files using erlang_exif 3.0.0.

  For images, the module attempts to extract the date/time from EXIF data and
  sets `:reliable` to true if successful; otherwise it falls back to the file's
  modification time (with `:reliable` false). In all cases, the file size, MD5 hash,
  and (if available) GPS information are included.
  """

  @image_extensions ~w(.jpg .jpeg .png .gif .bmp .tif .tiff)
  @video_extensions ~w(.mp4 .mov .avi .mkv .heic .vob .mpg .wmv)

  @doc """
  Extract metadata from the given file path.

  Returns:
    - `{:ok, %{datetime: datetime, reliable: reliable, file_size: file_size, md5: md5, gps: gps, type: type}}` on success.
    - `{:error, reason}` on failure.
  """
  def extract(file_path) when is_binary(file_path) do
    ext = file_path |> Path.extname() |> String.downcase()

    cond do
      ext in @image_extensions ->
        extract_image_metadata(file_path)

      ext in @video_extensions ->
        extract_video_metadata(file_path)

      true ->
        {:error, :unsupported_file_type}
    end
  end

  # For image files, try to read EXIF data.
  # If EXIF data contains a date/time, use it (and mark as reliable);
  # otherwise, fall back to the file's modification time.
  defp extract_image_metadata(file_path) do
    # Try reading EXIF data using erlang_exif.
    exif_result =
      try do
        case :erlang_exif.read(file_path) do
          {:ok, exif_data} -> {:ok, exif_data}
          :invalid_exif -> {:error, :invalid_exif}
          other -> {:error, other}
        end
      rescue
        _ -> {:error, :exif_read_failed}
      end

    # Get file stats and MD5 hash regardless of EXIF result.
    with {:ok, stat} <- File.stat(file_path),
         {:ok, md5} <- compute_md5(file_path) do
      case exif_result do
        {:ok, exif_data} ->
          # Sometimes the library returns a list of tuples; convert to a map if needed.
          exif_map = if is_list(exif_data), do: Enum.into(exif_data, %{}), else: exif_data

          # Keep exif_map value if it is a map, otherwise reassign it to the map if it matches {:ok, map}.
          exif_map = if is_map(exif_map), do: exif_map, else: elem(exif_map, 1)

          # Try to extract date/time from EXIF.
          exif_dt = get_datetime_from_exif(exif_map)
          reliable = exif_dt != nil and valid_datetime_format?(exif_dt)

          dt =
            if reliable do
              exif_dt
            else
              format_mod_time(stat.mtime)
            end

          gps = get_gps_from_exif(exif_map)

          {:ok,
           %{
             datetime: dt,
             reliable: reliable,
             file_size: stat.size,
             md5: md5,
             gps: gps,
             type: "photo"
           }}

        {:error, _reason} ->
          # If reading EXIF failed, fall back to modification time.
          dt = format_mod_time(stat.mtime)

          {:ok,
           %{
             datetime: dt,
             reliable: false,
             file_size: stat.size,
             md5: md5,
             gps: nil,
             type: "photo"
           }}
      end
    else
      error -> error
    end
  end

  # Check if the datetime string is in the "YYYY:MM:DD HH:MM:SS" format.
  defp valid_datetime_format?(datetime) do
    Regex.match?(~r/^\d{4}:\d{2}:\d{2} \d{2}:\d{2}:\d{2}$/, datetime) and
      not String.starts_with?(datetime, "0")
  end

  # For video files, there is no EXIF; use the file's modification time.
  defp extract_video_metadata(file_path) do
    with {:ok, stat} <- File.stat(file_path),
         {:ok, md5} <- compute_md5(file_path) do
      dt = format_mod_time(stat.mtime)

      {:ok,
       %{datetime: dt, reliable: false, file_size: stat.size, md5: md5, gps: nil, type: "video"}}
    else
      error -> error
    end
  end

  # ----------------------------------------------------------------------------
  # File MD5 Computation
  # ----------------------------------------------------------------------------

  # Compute the MD5 hash of the file contents and encode it as a compact Base64 string.
  defp compute_md5(file_path) do
    case File.read(file_path) do
      {:ok, binary} ->
        hash = :crypto.hash(:md5, binary)
        # Using Base64 with padding disabled produces a 22-character string.
        {:ok, Base.encode64(hash, padding: false)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ----------------------------------------------------------------------------
  # Modification Time Formatting
  # ----------------------------------------------------------------------------

  # Format modification time (a tuple) as a string "YYYY:MM:DD HH:MM:SS".
  defp format_mod_time({{year, month, day}, {hour, minute, second}}) do
    "#{pad(year)}:#{pad(month)}:#{pad(day)} #{pad(hour)}:#{pad(minute)}:#{pad(second)}"
  end

  defp pad(n) when is_integer(n) do
    Integer.to_string(n) |> String.pad_leading(2, "0")
  end

  # ----------------------------------------------------------------------------
  # EXIF Date/Time Extraction
  # ----------------------------------------------------------------------------

  # Try common EXIF keys for date/time.
  defp get_datetime_from_exif(exif_data) do
    Map.get(exif_data, "date_time_original") ||
      Map.get(exif_data, :date_time_original) ||
      Map.get(exif_data, "date_time") ||
      Map.get(exif_data, :date_time)
  end

  # ----------------------------------------------------------------------------
  # EXIF GPS Extraction
  # ----------------------------------------------------------------------------

  # Extract and compute GPS coordinates from the EXIF data.
  defp get_gps_from_exif(exif_data) do
    lat_list = Map.get(exif_data, "gps_latitude") || Map.get(exif_data, :gps_latitude)
    lon_list = Map.get(exif_data, "gps_longitude") || Map.get(exif_data, :gps_longitude)
    lat_ref = Map.get(exif_data, "gps_latitude_ref") || Map.get(exif_data, :gps_latitude_ref)
    lon_ref = Map.get(exif_data, "gps_longitude_ref") || Map.get(exif_data, :gps_longitude_ref)

    if is_list(lat_list) and is_list(lon_list) do
      lat = convert_gps(lat_list)
      lon = convert_gps(lon_list)

      # Adjust the sign based on the reference values (South/West should be negative).
      lat = apply_gps_ref(lat, lat_ref)
      lon = apply_gps_ref(lon, lon_ref)
      {lat, lon}
    else
      nil
    end
  end

  # Convert a list of three ratio tuples to a float (degrees in decimal form).
  defp convert_gps([deg, min, sec]) do
    deg_f = convert_ratio(deg)
    min_f = convert_ratio(min)
    sec_f = convert_ratio(sec)
    deg_f + min_f / 60.0 + sec_f / 3600.0
  end

  defp convert_gps(_), do: nil

  # Convert a ratio tuple {:ratio, numerator, denominator} to a float.
  defp convert_ratio({:ratio, num, den}) when den != 0, do: num / den
  defp convert_ratio(_), do: 0

  # Adjust the GPS coordinate based on its reference value.
  # If the reference indicates South or West, the value is negated.
  defp apply_gps_ref(value, ref) when is_binary(ref) do
    case ref do
      <<c, _rest::binary>> ->
        if c in [?S, ?W], do: -value, else: value

      _ ->
        value
    end
  end

  defp apply_gps_ref(value, _), do: value
end
