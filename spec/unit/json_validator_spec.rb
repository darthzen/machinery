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

describe JsonValidator do
  let(:v2_validator) { JsonValidator.new(2) }

  describe ".validate" do
    it "complains about invalid global data in a description" do
      errors = v2_validator.validate(JSON.parse(<<-EOT))
        {
          "meta": {
            "format_version": 2,
            "os": "invalid"
          }
        }
      EOT

      expect(errors).to_not be_empty
    end
  end

  describe ".valide_scope" do
    it "complains about invalid scope data in a description" do
      errors = v2_validator.validate_scope(JSON.parse(<<-EOT), "os")
        {
        }
      EOT

      expect(errors.length).to eq(3)
    end

    it "raises an error when encountering invalid enum values" do
      expected = <<EOF
In scope config_files: The property #0 (files/changes) of type Hash did not match any of the required schemas.
EOF

      errors = v2_validator.validate_scope(JSON.parse(<<-EOT), "config_files")
        {
          "extracted": true,
          "files": [
            {
              "name": "/etc/crontab",
              "package_name": "cronie",
              "package_version": "1.4.8",
              "status": "changed",
              "changes": [
                "invalid"
              ],
              "user": "root",
              "group": "root",
              "mode": "644"
            }
          ]
        }
      EOT

      expect(errors.first).to eq(expected.chomp)
    end

    it "does not raise an error when a changed-managed-file is 'replaced'" do
      errors = v2_validator.validate_scope(JSON.parse(<<-EOT), "changed_managed_files")
        {
          "extracted": true,
          "files": [
            {
              "name": "/etc/libvirt",
              "package_name": "libvirt-client",
              "package_version": "1.1.2",
              "status": "changed",
              "changes": [
                "replaced"
              ],
              "mode": "700",
              "user": "root",
              "group": "root"
            }
          ]
        }
      EOT

      expect(errors).to be_empty
    end

    context "config-files" do
      let(:path) { "spec/data/schema/validation_error/config_files/" }

      it "raises in case of missing package_version" do
        expected = <<EOF
In scope config_files: The property #0 (files) did not contain a required property of 'package_version'.
EOF
        expected.chomp!
        errors = v2_validator.validate_scope(
          JSON.parse(File.read("#{path}missing_attribute.json"))["config_files"],
          "config_files"
        )
        expect(errors.first).to eq(expected)
      end

      it "raises in case of an unknown status" do
        expected = <<EOF
In scope config_files: The property #0 (files/status) of type Hash did not match any of the required schemas.
EOF
        expected.chomp!
        expected.chomp!
        errors = v2_validator.validate_scope(
          JSON.parse(File.read("#{path}unknown_status.json"))["config_files"],
          "config_files"
        )
        expect(errors.first).to eq(expected)
      end

      it "raises in case of a pattern mismatch" do
        expected = <<EOF
In scope config_files: The property #0 (files/mode/changes) of type Hash did not match any of the required schemas.
EOF
        expected.chomp!
        expected.chomp!
        errors = v2_validator.validate_scope(
          JSON.parse(File.read("#{path}pattern_mismatch.json"))["config_files"],
          "config_files"
        )
        expect(errors.first).to eq(expected)
      end

      it "raises for a deleted file in case of an empty changes array" do
        expected = <<EOF
In scope config_files: The property #0 (files/changes) of type Hash did not match any of the required schemas.
EOF
        expected.chomp!
        expected.chomp!
        errors = v2_validator.validate_scope(
          JSON.parse(File.read("#{path}deleted_without_changes.json"))["config_files"],
          "config_files"
        )
        expect(errors.first).to eq(expected)
      end
    end

    context "unmanaged_files scope" do
      let(:path) { "spec/data/schema/validation_error/unmanaged_files/" }

      it "raises for extracted in case of unknown type" do
        expected = <<EOF
In scope unmanaged_files: The property #0 (files) of type Array did not match any of the required schemas.
EOF
        expected.chomp!
        expected.chomp!
        errors = v2_validator.validate_scope(
          JSON.parse(File.read("#{path}extracted_unknown_type.json"))["unmanaged_files"],
          "unmanaged_files"
        )
        expect(errors.first).to eq(expected)
      end
    end
  end

  describe "#cleanup_json_error_message" do
    let (:validator)  { JsonValidator.new(2) }
    describe "shows the correct position and reduces the clutter" do
      it "for missing attribute in unmanaged-files errors" do
        error = "The property '#/0/type/0/1/2/3/type/4/5' of type Array did not match any of the required schemas in schema 89d6911a-763e-51fd-8e35-257a1f31d377#"
        expected = "The property #5 of type Array did not match any of the required schemas."
        expect(validator.send(:cleanup_json_error_message, error, "unmanaged_files")).
          to eq(expected)
      end

      it " for missing attribute in unmanaged_files and filters the type elements" do
        error = "The property '#/0/type/0/1/2/3/type/4/5/type/6/type/7/8/9/10/11/type/12/17/18/19/20/21/22/23/24/25/26/27/28/29/type/30/31/33/34/35/36/37/38/39/40/41/42/43/44/45/46/47/48/49/476/477/478/479/480/481/482/483/484/485/486/487/488/489/490/491/492/493/494/495/496/497/498/499/500/501/504/type/505/type/506/type/507/type/508/type/509/510/511/512/513/514/515/516/517/518/519/520/type/555' of type Array did not match any of the required schemas in schema 89d6911a-763e-51fd-8e35-257a1f31d377#"
        expected = "The property #555 of type Array did not match any of the required schemas."
        expect(validator.send(:cleanup_json_error_message, error, "unmanaged_files")).
          to eq(expected)
      end

      it "for missing attribute in services" do
        error = "The property '#/services/2' did not contain a required property of 'state' in schema 73e30722-b9a4-573a-95a9-1f6882dd11a5#"
        expected = "The property #2 (services) did not contain a required property of 'state'."
        expect(validator.send(:cleanup_json_error_message, error, "services")).
          to eq(expected)
      end

      it "for wrong status in services" do
        error = "The property '#/services/4/state' was not of a minimum string length of 1 in schema 73e30722-b9a4-573a-95a9-1f6882dd11a5#"
        expected = "The property #4 (services/state) was not of a minimum string length of 1."
        expect(validator.send(:cleanup_json_error_message, error, "services")).
          to eq(expected)
      end

      it "for missing attribute in os" do
        error = "The property '#/' did not contain a required property of 'version' in schema 547e11fe-8e4b-574a-bec5-66ada4e5e2ec#"
        expected = "The property did not contain a required property of 'version'."
        expect(validator.send(:cleanup_json_error_message, error, "os")).
          to eq(expected)
      end

      it "for wrong attribute type in users" do
        error = "The property '#/3/gid' of type String did not match one or more of the following types: integer, null in schema 769f5514-0330-592b-b538-87df746cb3d3#"
        expected = "The property #3 (gid) of type String did not match one or more of the following types: integer, null."
        expect(validator.send(:cleanup_json_error_message, error, "users")).
          to eq(expected)
      end

      it "for unknown repository type and mentions the affected attribute 'type'" do
        error = "The property '#/4/type' value 0 did not match one of the following values: yast2, rpm-md, plaindir, null in schema 5ee44188-86f1-5823-92ac-e1068304cbf2#"
        expected = "The property #4 (type) value 0 did not match one of the following values: yast2, rpm-md, plaindir, null."
        expect(validator.send(:cleanup_json_error_message, error, "repositories")).
          to eq(expected)
      end

      it "for unknown status in config-files" do
        error = "The property '#/0/1/status' of type Hash did not match any of the required schemas in schema 5257ca96-7f5c-5c72-b44e-80abca5b0f38#"
        expected = "The property #1 (status) of type Hash did not match any of the required schemas."
        expect(validator.send(:cleanup_json_error_message, error, "config_files")).
          to eq(expected)
      end
    end
  end
end