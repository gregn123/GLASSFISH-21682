setlocal

set GF_HOME=D:\Users\NancarrowG\Work\glassfish5\glassfish4
set PATH=%GF_HOME%\glassfish\bin;%PATH%
set JAVA_HOME=c:\Program Files\Java\jdk1.8.0_121


REM call asadmin start-domain
call asadmin start-database

call asadmin enable-monitoring  --modules jdbc-connection-pool --target server

call asadmin stop-domain
call asadmin start-domain

call asadmin create-jdbc-connection-pool --datasourceclassname org.apache.derby.jdbc.ClientDataSource --maxpoolsize=5  --isconnectvalidatereq=true --validationmethod=table --validationtable=SYS.SYSTABLES --failconnection=true  --poolresize=2 --steadypoolsize=5 --restype=javax.sql.DataSource --property user=APP:databasename=my-db:servername=localhost:portnumber=1527:password=APP:connectionattributes=;create\=true TestConnPoolBugPool

call asadmin create-jdbc-resource --target server --connectionpoolid TestConnPoolBugPool jdbc/TestConnPoolBug 

call asadmin deploy --target server TestConnPoolBug.war

echo Done.

endlocal




