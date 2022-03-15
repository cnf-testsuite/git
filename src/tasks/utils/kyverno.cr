require "http/client"

module Kyverno
  VERSION = "1.6.1"

  def self.binary_path
    "#{tools_path}/kyverno"
  end

  def self.install
    cli_path = "#{tools_path}/kyverno"
    return true if File.exists?(cli_path)
    tempfile = File.tempfile("kyverno", ".tar.gz")

    HTTP::Client.get(download_url) do |response|
      if response.status_code == 302
        redirect_url = response.headers["Location"]
        HTTP::Client.get(redirect_url) do |response|
          File.write(tempfile.path, response.body_io)
        end
      end
    end

    result = TarClient.untar(tempfile.path, tools_path)
    tempfile.delete
    download_policies_repo
    return true if result[:status].success?
    return false
  end

  def self.uninstall
    FileUtils.rm_rf(binary_path)
    delete_policies_repo
    KubectlClient::Get.resource_wait_for_uninstall("deployment", "kyverno", 180, "kyverno")
  end

  def self.download_url
    # Support different flavours of Linux and MacOS
    flavour = ""
    {% if flag?(:linux) && flag?(:x86_64) %}
      flavour = "linux_x86_64"
    {% elsif flag?(:linux) && flag?(:aarch64) %}
      flavour = "linux_arm64"
    {% elsif flag?(:darwin) && flag?(:x86_64) %}
      flavour = "darwin_x86_64"
    {% elsif flag?(:darwin) && flag?(:aarch64) %}
      flavour = "darwin_arm64"
    {% end %}

    file_name = "kyverno-cli_v#{VERSION}_#{flavour}.tar.gz"
    "https://github.com/kyverno/kyverno/releases/download/v#{VERSION}/#{file_name}"
  end

  def self.best_practice_policy(policy_path : String) : String
    "#{policies_repo_path}/best-practices/#{policy_path}"
  end

  def self.policies_repo_path
    "#{tools_path}/kyverno-policies"
  end

  def self.download_policies_repo
    url = "https://github.com/kyverno/policies.git"
    result = GitClient.clone("#{url} #{policies_repo_path}")
    result[:status].success?
  end

  def self.delete_policies_repo
    FileUtils.rm_rf(policies_repo_path)
  end

  module PolicyAudit
    struct FailedResource
      property kind
      property name
      property namespace

      def initialize(@kind : String, @name : String, @namespace : String)
      end
    end

    struct PolicyFailure
      property message
      property resources

      def initialize(@message : String, @resources : Array(FailedResource))
      end
    end

    def self.run(policy_path : String, exclude_namespaces : Array(String) = [] of String)
      cmd = "#{Kyverno.binary_path} apply #{policy_path} --cluster --policy-report"
      ShellCmd.run("ls #{policy_path}", "kyverno_policy_path", force_output: true)
      result = ShellCmd.run(cmd, "Kyverno::PolicyAudit.run", force_output: true)
      Log.for("kyverno_audit").info { result[:output] }
      policy_report_yaml = result[:output].split("\n")[6..-1].join("\n")
      policy_report = YAML.parse(policy_report_yaml)

      failures = [] of PolicyFailure
      policy_report["results"].as_a.each do |test_result|
        if test_result["result"] == "fail"
          failed_resources = test_result["resources"].as_a.reduce([] of FailedResource) do |acc, resource|
            if exclude_namespaces.includes?(resource["namespace"])
              acc
            else
              acc << FailedResource.new(resource["kind"].to_s, resource["name"].to_s, resource["namespace"].to_s)
            end
          end

          if failed_resources.size > 0
            policy_failure = PolicyFailure.new(test_result["message"].to_s, failed_resources)
            failures.push(policy_failure)
          end
        end
      end

      failures
    end
  end

end
