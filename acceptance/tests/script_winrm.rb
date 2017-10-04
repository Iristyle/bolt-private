test_name "C100549: bolt script run should execute command on remote hosts via winrm" do
  script = "C100549.ps1"
  step "create script on bolt controller" do
    create_remote_file(bolt, script, <<-FILE)
    [System.Net.Dns]::GetHostByName(($env:computerName))
    FILE
  end
  step "execute `bolt command run` via WinRM" do
    winrm_nodes = select_hosts({:roles => ['winrm']})
    nodes_csv = winrm_nodes.map { |host| "winrm://#{host.hostname}" }.join(',')
    bolt_command = "bolt script run --nodes #{nodes_csv} #{script}"
    case bolt['platform']
    when /windows/
      result = execute_powershell_script_on(bolt, bolt_command)
    else
      result = on(bolt, bolt_command)
    end
    # assert something on result
  end
end
