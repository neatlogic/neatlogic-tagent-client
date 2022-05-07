#!/bin/bash
cd $(dirname $0)/../../.. || exit 1;

#cd /home/wenhb/workspace/deploysys-v3/tools || exit 1;

for ip in `cat tools/tagent/tmp/iplist.txt`
do
        tools/tagent/tools/sshexec -v -h $ip -u root --pass techsure 'service tagent stop'
	tools/tagent/tools/scpexec -v -h $ip -u root --pass techsure tools/tagent/bin tools/tagent/tools tools/tagent/lib tools/tagent/mod /opt/tagent/
        tools/tagent/tools/scpexec -v -h $ip -u root --pass techsure tools/tagent/bin tools/tagent/tools tools/tagent/lib tools/tagent/mod /app/ezdeploy/tools/tagent/ 
        tools/tagent/tools/scpexec -v -h $ip -u root --pass techsure lib/* /app/ezdeploy/lib/
        tools/tagent/tools/scpexec -v -h $ip -u root --pass techsure bin/* /app/ezdeploy/bin/
        tools/tagent/tools/scpexec -v -h $ip -u root --pass techsure tools/ezdplyfssb* /app/ezdeploy/tools/
        tools/tagent/tools/scpexec -v -h $ip -u root --pass techsure tools/windeploy /app/ezdeploy/tools/
        tools/tagent/tools/scpexec -v -h $ip -u root --pass techsure tools/tagent/lib/TagentClient.pm /app/ezdeploy/lib/

        tools/tagent/tools/sshexec -v -h $ip -u root --pass techsure 'service tagent restart;ps -ef|grep tagent'
done

ip="192.168.0.26"
tools/tagent/tools/sshexec -v -h $ip -u root 'service tagent stop'
tools/tagent/tools/scpexec -v -h $ip -u root tools/tagent/bin tools/tagent/tools tools/tagent/lib tools/tagent/mod /opt/tagent/
tools/tagent/tools/scpexec -v -h $ip -u root tools/tagent/bin tools/tagent/tools tools/tagent/lib tools/tagent/mod /app/ezdeploy/tools/tagent/
tools/tagent/tools/scpexec -v -h $ip -u root lib/* /app/ezdeploy/lib/
tools/tagent/tools/scpexec -v -h $ip -u root tools/ezdplyfssb* /app/ezdeploy/tools/
tools/tagent/tools/scpexec -v -h $ip -u root tools/windeploy /app/ezdeploy/tools/
tools/tagent/tools/scpexec -v -h $ip -u root bin/* /app/ezdeploy/bin/
tools/tagent/tools/scpexec -v -h $ip -u root tools/tagent/lib/TagentClient.pm /app/ezdeploy/lib/

tools/tagent/tools/sshexec -v -h $ip -u root 'service tagent restart;ps -ef|grep tagent'


