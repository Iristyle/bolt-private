test_name "C100547: bolt command run should execute command on remote hosts via winrm" do
  step "execute `bolt command run` via WinRM" do
    winrm_nodes = select_hosts({:roles => ['winrm']})
    nodes_csv = winrm_nodes.map { |host| "winrm://#{host.hostname}" }.join(',')
    command = '[System.Net.Dns]::GetHostByName(($env:computerName))'
    bolt_command = "bolt command run --nodes #{nodes_csv} '#{command}'"
    case bolt['platform']
    when /windows/
      result = execute_powershell_script_on(bolt, bolt_command)
    else
      result = on(bolt, bolt_command)
    end
    # assert something on the result
  end
end
