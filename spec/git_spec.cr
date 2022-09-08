require "./spec_helper"
require "colorize"
require "../src/git.cr"

describe "Git" do

  it "'installation_found?' should show a git client was located",  do
    (GitClient.installation_found?).should be_true
  end
end
