require 'spec_helper'

describe Codelog::Command::Step::Version do
  let(:outputter) { double(:mocked_outputter) }
  before(:each) { allow(outputter).to receive(:print) }

  describe '#new' do
    it 'aborts when date format differs than the provided one' do
      allow_any_instance_of(described_class).to receive(:config_file_exists?) { true }
      allow(Codelog::Config).to receive(:date_input_format) { '%Y-%m-%d' }
      expect_any_instance_of(described_class).to receive(:abort).with Codelog::Message::Error.invalid_date_format
      described_class.new('1.2.4', '2012/12/12', outputter)
    end

    context 'when config file is not provided' do
      before(:each) do
        allow_any_instance_of(described_class).to receive(:config_file_exists?) { false }
      end

      it 'aborts with the appropriate message' do
        expect_any_instance_of(described_class).to receive(:abort).with Codelog::Message::Error.missing_config_file
        described_class.new('1.2.3', '2012-12-31', outputter)
      end
    end
  end

  describe '#run' do
    subject { described_class.new('1.2.3', '2012-12-12', outputter) }

    let(:mocked_string_io) { double(StringIO) }

    before :each do
      allow(Dir).to receive(:"[]").with('changelogs/unreleased/*.yml') do
        ['file_1.yml', 'file_2.yml']
      end
      allow(YAML).to receive(:load_file).with('file_1.yml') { { 'Category_1' => ['value_1'] } }
      allow(YAML).to receive(:load_file).with('file_2.yml') { { 'Category_1' => ['value_2', { 'Subcategory_1' => 'value_3' } ] } }
      allow(Codelog::Config).to receive(:date_input_format) { '%Y-%m-%d' }
      allow_any_instance_of(described_class).to receive(:config_file_exists?) { true }
    end

    # Todo: Fix Calling `DidYouMean::SPELL_CHECKERS.merge!(error_name => spell_checker)' has been deprecated
    context "within normal run" do
      before :each do
        allow(File).to receive(:file?).and_return(false)
        allow(subject).to receive(:unreleased_changes?).and_return(true)
        allow(Codelog::Config).to receive(:version_tag)
          .with('1.2.3', '2012-12-12') { '1.2.3 2012-12-12' }
      end

      it 'merges the content of the files with the same category' do
        expect(subject).to receive(:generate_changelog_content_from)
          .with({ 'Category_1' => ['value_1', 'value_2', { 'Subcategory_1' => 'value_3' }] })
        subject.run
      end

      it 'generates the release content using the unreleased changes' do
        allow(StringIO).to receive(:new).and_return mocked_string_io
        allow(mocked_string_io).to receive(:puts)
        allow(mocked_string_io).to receive(:string)

        subject.run

        expect(mocked_string_io).to have_received(:puts).with '## 1.2.3 2012-12-12'
        expect(mocked_string_io).to have_received(:puts).with '### Category_1'
        expect(mocked_string_io).to have_received(:puts).with '- Subcategory_1'
        expect(mocked_string_io).to have_received(:puts).with "\t- value_3"
        expect(mocked_string_io).to have_received(:string)
      end

      it 'checks the existence of an already existing version of the release' do
        expect(subject).to receive(:version_exists?)
        subject.run
      end

      it 'checks the existence of change files' do
        expect(subject).to receive(:unreleased_changes?)
        subject.run
      end

      it 'calls the print method on the passed outputter' do
        allow_any_instance_of(described_class).to receive(:generate_changelog_content_from).and_return('test')
        expect(outputter).to receive(:print).with('test')

        subject.run
      end
    end

    context "within a failed run" do
      describe 'without a given version' do
        before :each do
          allow(File).to receive(:file?).with('changelogs/releases/.md').and_return(false)
          allow(subject).to receive(:unreleased_changes?).and_return(true)
          allow(Codelog::Config).to receive(:version_tag).with(nil, '2012-12-12')
        end

        subject { described_class.new(nil, '2012-12-12', outputter) }

        it 'aborts with the appropriate error message' do
          expect(subject).to receive(:abort).with Codelog::Message::Error.missing_version_number

          subject.run
        end
      end

      describe 'with an already existing version' do
        before do
          allow(subject).to receive(:version_exists?).and_return(true)
          allow(Codelog::Config).to receive(:version_tag).with('1.2.3', '2012-12-12')
        end

        it 'aborts with the appropriate error message' do
          expect(subject).to receive(:abort).with Codelog::Message::Error.already_existing_version('1.2.3')
          subject.run
        end
      end

      describe 'with no changes to be released' do
        before :each do
          allow(File).to receive(:file?).and_return(false)
          allow(Dir).to receive(:"[]").with('changelogs/unreleased/*.yml').and_return([])
          allow(Codelog::Config).to receive(:version_tag).with('1.2.3', '2012-12-12')
        end

        it 'aborts with the appropriate error message' do
          expect(subject).to receive(:abort).with Codelog::Message::Error.no_detected_changes('1.2.3')

          subject.run
        end
      end
    end
  end

  describe '.run' do
    it 'creates an instance of the class to run the command' do
      allow_any_instance_of(described_class).to receive(:config_file_exists?) { true }
      allow(Codelog::Config).to receive(:date_input_format) { '%Y-%m-%d' }
      expect_any_instance_of(described_class).to receive(:run)
      described_class.run('1.2.4', '2012-12-12', outputter)
    end
  end

  describe '#changes_hash' do
    context "when a non parseable yml file is given" do
      subject { described_class.new('1.2.3', '2012-12-12', outputter) }

      it 'aborts with the appropriate message' do
        allow(Dir).to receive(:"[]") { ["spec/fixtures/files/not_parseable.yml"] }
        # Regex will match the error message raised by SystemExit both Ruby and JRuby
        expect { subject.run }.to raise_error(SystemExit)
          .with_message(/ERROR: Found character(.)*that cannot start any token(.)*in spec\/fixtures\/files\/not_parseable.yml:3/)
      end
    end
  end
end
