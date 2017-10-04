test_name "C100548: bolt script run should execute command on remote hosts via ssh" do
  script = "C100548.sh"
  step "create script on bolt controller" do
    create_remote_file(bolt, script, <<-FILE)
    #!/bin/sh
    hostname -f
    FILE
  end
  step "execute `bolt command run` via SSH" do
    ssh_nodes = select_hosts({:roles => ['ssh']})
    nodes_csv = ssh_nodes.map { |host| host.hostname }.join(',')
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
