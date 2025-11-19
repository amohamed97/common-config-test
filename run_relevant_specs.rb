#!/usr/bin/env ruby
# frozen_string_literal: true

# Run only relevant specs for changed files compared to main branch
# This script maps changed files to their corresponding spec files and runs them

require 'set'
require 'fileutils'

class RelevantSpecRunner
  def initialize
    @repo_root = `git rev-parse --show-toplevel 2>/dev/null`.strip
    exit 0 if @repo_root.empty?

    Dir.chdir(@repo_root)
    @spec_files = Set.new
  end

  def run
    changed_files = get_changed_files

    if changed_files.empty?
      warn "[relevant-specs] No changed files detected; allowing push."
      exit 0
    end

    map_files_to_specs(changed_files)

    if @spec_files.empty?
      warn "[relevant-specs] No relevant unit specs found; allowing push."
      exit 0
    end

    display_specs_to_run

    # Uncomment this to prompt the user for confirmation
    # return unless prompt_user?

    run_specs
  end

  private

  def get_changed_files
    base = find_base_branch
    return [] if base.nil?

    `git diff --name-only #{base} HEAD`.split("\n").map(&:strip).reject(&:empty?)
  end

  def find_base_branch
    base = `git merge-base origin/main HEAD 2>/dev/null`.strip
    return base unless base.empty?

    warn "[relevant-specs] Warning: Could not find origin/main"
    nil
  end

  def map_files_to_specs(files)
    files.each do |file|
      spec = map_spec(file)
      add_spec(spec) if spec && File.exist?(spec)
    end
  end

  def map_spec(path)
    case path
    # Direct 1:1 mappings
    when %r{^app/models/(.+)\.rb$}
      "spec/models/#{$1}_spec.rb"
    when %r{^app/controllers/(.+)\.rb$}
      "spec/controllers/#{$1}_spec.rb"
    when %r{^app/services/(.+)\.rb$}
      "spec/services/#{$1}_spec.rb"
    when %r{^lib/(.+)\.rb$}
      "spec/lib/#{$1}_spec.rb"
    when %r{^app/helpers/(.+)\.rb$}
      "spec/helpers/#{$1}_spec.rb"
    when %r{^app/queries/(.+)\.rb$}
      "spec/queries/#{$1}_spec.rb"
    when %r{^app/decorators/(.+)\.rb$}
      "spec/decorators/#{$1}_spec.rb"
    when %r{^app/mailers/(.+)\.rb$}
      "spec/mailers/#{$1}_spec.rb"
    when %r{^app/jobs/(.+)\.rb$}
      "spec/jobs/#{$1}_spec.rb"
    when %r{^app/observers/(.+)\.rb$}
      "spec/observers/#{$1}_spec.rb"

    # Spec files themselves
    when %r{^spec/.+_spec\.rb$}
      path

    else
      nil
    end
  end

  def add_spec(spec)
    @spec_files.add(spec)
  end

  def display_specs_to_run
    warn "[relevant-specs] Running changed unit specs:"
    @spec_files.sort.each do |spec|
      warn "  #{spec}"
    end
  end

  def prompt_user?
    # Check if we can prompt via TTY
    return true unless File.exist?('/dev/tty')

    print "[relevant-specs] Run these specs now? [Y/n] "
    STDOUT.flush

    # Read from /dev/tty instead of STDIN (which git uses for hook data)
    File.open('/dev/tty', 'r') do |tty|
      response = tty.gets.to_s.strip.downcase
      return response.empty? || !['n', 'no'].include?(response)
    end
  rescue => e
    # If we can't prompt, proceed with running specs
    warn "[relevant-specs] Cannot prompt (#{e.message}); proceeding with specs."
    true
  end

  def run_specs
    spec_list = @spec_files.sort.join(' ')

    # Run specs and capture success status
    if system("bundle exec rspec --format progress --fail-fast #{spec_list}")
      exit 0
    else
      handle_failed_specs
    end
  end

  def handle_failed_specs
    if prompt_to_proceed?
      warn "[relevant-specs] Proceeding with push despite spec failures."
      exit 0
    else
      warn "[relevant-specs] Push aborted. Please fix the specs."
      exit 1
    end
  end

  def prompt_to_proceed?
    # If we can't prompt, we assume failure
    return false unless File.exist?('/dev/tty')

    warn "\n[relevant-specs] Some specs failed."
    print "[relevant-specs] Do you want to proceed with the push anyway? [y/N] "
    STDOUT.flush

    begin
      File.open('/dev/tty', 'r') do |tty|
        response = tty.gets.to_s.strip.downcase
        return ['y', 'yes'].include?(response)
      end
    rescue => e
      warn "[relevant-specs] Cannot prompt (#{e.message}); aborting."
      false
    end
  end
end

# Run the script
if __FILE__ == $0
  runner = RelevantSpecRunner.new
  runner.run
end
