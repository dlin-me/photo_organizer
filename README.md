# PhotoOrganizer

PhotoOrganizer is a simple command-line tool for organizing photos and videos by copying them from a source directory to a target directory using a specific naming scheme. It also records file info in a CubDB database to avoid duplicates.

## Purpose

The main purpose of PhotoOrganizer is to help you organize your photos and videos into a structured directory format based on the date they were taken. It also identifies and handles duplicate files to ensure that your media library remains clean and organized.

## Features

- Organizes photos and videos into directories based on the date they were taken (YYYY/MM/DD).
- Identifies and handles duplicate files by moving them to a separate "duplication" directory.
- Extracts metadata from media files, including date/time, file size, MD5 hash, and GPS information (if available).
- Optionally rebuilds the database index for media files in the target directory.
- Reports the total number of files in the database.

## Requirements

- Elixir ~> 1.17
- Erlang

## Installation

To get started with development, follow these steps:

1. **Clone the repository**:
   ```sh
   git clone https://github.com/yourusername/photo_organizer.git
   cd photo_organizer
   ```

2. **Install dependencies**:
   ```sh
   mix deps.get
   ```

3. **Compile the project**:
   ```sh
   mix compile
   ```

4. **Build the escript**:
   ```sh
   mix escript.build
   ```

This will generate the `po` executable in the project root directory.

## Usage

The repository comes with a compiled `po` executable. To run it, make sure Erlang is installed on your system.

```sh
./po <source_dir> <target_dir>
```

The `po` command provides three subcommands: `import`, `index`, and `report`.

### Import

The `import` command imports photos and videos from a source directory to a target directory. If the target directory is not specified, it defaults to the current directory.

```sh
po import SOURCE_DIR [TARGET_DIR]
```

- `SOURCE_DIR`: The directory containing the media files to import.
- `TARGET_DIR`: (Optional) The directory to import the media files into. Defaults to the current directory.

### Index

The `index` command rebuilds the database index for media files in the target directory. If the target directory is not specified, it defaults to the current directory.

```sh
po index [TARGET_DIR]
```

- `TARGET_DIR`: (Optional) The directory containing the media files to index. Defaults to the current directory.

### Report

The `report` command reports the total number of files in the database in the target directory. If the target directory is not specified, it defaults to the current directory.

```sh
po report [TARGET_DIR]
```

- `TARGET_DIR`: (Optional) The directory containing the database to report on. Defaults to the current directory.

