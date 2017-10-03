gem_source = ENV['GEM_SOURCE'] || "https://rubygems.org"
gem_version = ENV['BOLT_GEM'] || "> 0.1.0"

test_name "Install Bolt gem" do
  step "Install Bolt gem" do
    install_command = "gem install --source #{gem_source} bolt -v '#{gem_version}'"
    result = nil
    case bolt['platform']
    when /windows/
      execute_powershell_script_on(bolt, install_command)
      result = on(bolt, powershell('bolt --help'))
    else
      on(bolt, install_command)
      result = on(bolt, 'bolt --help')
    end
    assert_match(/Usage: bolt <subcommand>/, result.stdout)
  end
end
