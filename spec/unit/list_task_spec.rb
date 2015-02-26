# Copyright (c) 2013-2015 SUSE LLC
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

require_relative "spec_helper"

describe ListTask do
  include FakeFS::SpecHelpers
  let(:list_task) { ListTask.new }
  let(:store) { SystemDescriptionStore.new }
  let(:name) { "foo" }
  let(:date) { "2014-02-07T14:04:45Z" }
  let(:hostname) { "example.com" }
  let(:date_human) { Time.parse(date).localtime.strftime "%Y-%m-%d %H:%M:%S" }
  let(:system_description) {
    create_test_description(
      scopes: ["packages", "repositories"], modified: date, hostname: hostname,
      name: name, store: store
    )
  }
  let(:system_description_without_scope_meta) {
    create_test_description(scopes: ["packages"], add_scope_meta: false, name: name, store: store)
  }
  let(:system_description_with_extracted_files) {
    create_test_description(
      scopes: ["changed_managed_files"],
      extracted_scopes: ["config_files", "unmanaged_files"],
      name: name, store: store)
  }
  let(:system_description_with_newer_data_format) {
    create_test_description(json: <<-EOF, name: name, store: store)
      { "meta": { "format_version": #{SystemDescription::CURRENT_FORMAT_VERSION + 1} } }
    EOF
  }
  let(:system_description_with_old_data_format) {
    create_test_description(json: <<-EOF, name: name, store: store)
      { "meta": { "format_version": 1 } }
    EOF
  }
  let(:system_description_with_incompatible_data_format) {
    create_test_description(json: <<-EOF, name: name, store: store)
      {}
    EOF
  }

  describe "#list" do
    before(:each) do
      allow(JsonValidator).to receive(:new).and_return(double(validate: []))
    end

    it "lists the system descriptions with scopes" do
      system_description.save
      expect(Machinery::Ui).to receive(:puts) { |s|
        expect(s).to include(name)
        expect(s).to include("packages")
        expect(s).to include("repositories")
        expect(s).not_to include(date_human)
        expect(s).not_to include(hostname)
      }
      list_task.list(store)
    end

    it "shows also the date and hostname of the descriptions if verbose is true" do
      system_description.save
      expect(Machinery::Ui).to receive(:puts) { |s|
        expect(s).to include(name)
        expect(s).to include(date_human)
        expect(s).to include(hostname)
      }
      list_task.list(store, verbose: true)
    end

    it "verbose shows the date/hostname as unknown if there is no meta data for it" do
      system_description_without_scope_meta.save
      expect(Machinery::Ui).to receive(:puts) { |s|
        expect(s).to include(name)
        expect(s).to include("unknown")
        expect(s).to include("Unknown hostname")
      }
      list_task.list(store, verbose: true)
    end

    it "show the extracted state of extractable scopes" do
      allow_any_instance_of(SystemDescription).to receive(:validate_file_data)
      expect(Machinery::Ui).to receive(:puts) { |s|
        expect(s).to include(name)
        expect(s).to include("config-files (extracted)")
        expect(s).to include("changed-managed-files (not extracted)")
      }

      system_description_with_extracted_files.save
      list_task.list(store)
    end

    it "marks descriptions with old data format" do
      expect(Machinery::Ui).to receive(:puts) { |s|
        expect(s.to_s).to include("needs to be upgraded.")
      }
      system_description_with_old_data_format.save
      list_task.list(store)
    end

    it "marks descriptions with incompatible data format" do
      expect(Machinery::Ui).to receive(:puts) { |s|
        expect(s.to_s).to include("Can not be upgraded.")
      }
      system_description_with_incompatible_data_format.save
      list_task.list(store)
    end

    it "marks descriptions with newer data format" do
      expect(Machinery::Ui).to receive(:puts) { |s|
        expect(s.to_s).to include("upgrade Machinery")
      }
      system_description_with_newer_data_format.save
      list_task.list(store)
    end
  end
end
