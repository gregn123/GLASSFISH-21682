setlocal

set GF_HOME=D:\Users\NancarrowG\Work\glassfish5\glassfish4
set PATH=%GF_HOME%\glassfish\bin;%PATH%
set JAVA_HOME=c:\Program Files\Java\jdk1.8.0_121

call asadmin delete-jdbc-resource jdbc/TestConnPoolBug 
call asadmin delete-jdbc-connection-pool TestConnPoolBugPool

call asadmin undeploy --target server TestConnPoolBug

call asadmin disable-monitoring  --modules jdbc-connection-pool --target server

call asadmin stop-domain
call asadmin start-domain

echo Done.

endlocal


