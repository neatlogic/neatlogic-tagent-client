echo off
net stop Tagent-Server
tssm remove Tagent-Server confirm
"%CD%\Perl\bin\perl" -i.bak -pe "s/tagent\.id=.*/tagent.id=/" "%CD%\conf\tagent.conf"
