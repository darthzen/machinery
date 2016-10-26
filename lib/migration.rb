# Copyright (c) 2013-2016 SUSE LLC
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of version 3 of the GNU General Public License as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.   See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, contact SUSE LLC.
#
# To contact SUSE about this file by physical or electronic mail,
# you may find current contact information at www.suse.com

# = SystemDescription Migrations
#
# Migrations are used for migrating descriptions with an older format version to
# the current version. They are defined as subclasses of `Migration` in
# `schema/migrations`.
#
# == Naming schema
#
# Migrations need to follow a naming schema defining which format version they
# are working on. `Migrate1To2` defines a migration which converts a version 1
# description to a version 2 one, for example.
#
# == Defining migrations
#
# The migration classes need to define a `migrate` method which does the actual
# migration. The raw hash of the system description in question is made
# available as the `@hash` instance variable, the path to the description on
# disk is given ash the `@path` instance variable.
#
# Migrations also need to describe their purpose using the `desc` class method
# (see example below).
#
# *Note*: Migrations do not need to take care of updating the format version
# attribute in the system description. That is already handled by the base
# class.
#
# Simple example migration which adds a new attribute to the JSON:
#
#   class Machinery::Migrate1To2 < Machinery::Migration
#     desc <<-EOT
#       Add 'foo' element to the system description root.
#     EOT
#
#     def migrate
#       is_extracted = Dir.exist?(File.join(@path, "config-files"))
#       @hash["changed_config_files"]["extracted"] = is_extracted
#     end
#   end
class Machinery::Migration
  MIGRATIONS_DIR= File.join(Machinery::ROOT, "schema/migrations")

  class << self
    attr_reader :migration_desc

    def desc(s)
      @migration_desc = s
    end

    def migrate_description(store, description_name, options = {})
      load_migrations

      hash = Machinery::Manifest.load(
        description_name,
        store.manifest_path(description_name)
      ).to_hash

      errors = Machinery::JsonValidator.new(hash).validate
      errors += Machinery::FileValidator.new(
        hash,
        store.description_path(description_name)
      ).validate
      unless errors.empty?
        if options[:force]
          Machinery::Ui.warn("Warning: System Description validation errors:")
          Machinery::Ui.warn(errors.join(", "))
        else
          raise Machinery::Errors::SystemDescriptionValidationFailed.new(errors)
        end
      end

      current_version = hash["meta"]["format_version"]
      unless current_version
        raise Machinery::Errors::SystemDescriptionIncompatible.new(
          "The system description '#{description_name}' was generated by an old " \
          "version of machinery that is not supported by the upgrade mechanism."
        )
      end

      if current_version == Machinery::SystemDescription::CURRENT_FORMAT_VERSION
        Machinery::Ui.puts "No upgrade necessary."
        return false
      end

      backup_description = store.backup(description_name)
      backup_path = store.description_path(backup_description)
      backup_hash = Machinery::Manifest.load(
        backup_description, store.manifest_path(backup_description)
      ).to_hash

      (current_version..Machinery::SystemDescription::CURRENT_FORMAT_VERSION - 1).each do |version|
        next_version = version + 1
        begin
          klass = Object.const_get("Machinery::Migrate#{version}To#{next_version}")
        rescue NameError
          return
        end

        # Make sure that the migration was documented
        if klass.migration_desc.nil?
          raise Machinery::Errors::MigrationError.new(
            "Invalid migration '#{klass}'. It does not specify its purpose using" \
            " the 'desc' class method."
          )
        end

        klass.new(backup_hash, backup_path).migrate
        backup_hash["meta"]["format_version"] = next_version
      end

      File.write(store.manifest_path(backup_description), JSON.pretty_generate(backup_hash))

      if options[:force]
        store.swap(description_name, backup_description)
        Machinery::Ui.puts "Saved backup to #{backup_path}"
      else
        begin
          Machinery::SystemDescription.load!(backup_description, store)
          store.remove(description_name)
          store.rename(backup_description, description_name)
        rescue Machinery::Errors::SystemDescriptionError
          store.remove(backup_description)
          raise
        end
      end

      true
    end

    private

    def load_migrations
      Dir.glob(File.join(MIGRATIONS_DIR, "*")).each do |migration|
        require migration
      end
    end
  end

  attr_accessor :hash
  attr_accessor :path

  abstract_method :migrate

  def initialize(hash, path)
    @hash = hash
    @path = path
  end
end
