## Setting Up Postgre on remote server
1 . `sudo apt install postgresql -y`

2 . `sudo su postgres`

3 . `psql -U  postgres -c "CREATE ROLE ubuntu;"`

4 . `psql -U  postgres -c "ALTER ROLE ubuntu WITH LOGIN;"`

5 .` psql -U  postgres -c "ALTER ROLE ubuntu CREATEDB;"`

6 . `psql -U  postgres -c "ALTER ROLE ubuntu WITH PASSWORD '1234';"`

7 . Then exit from psql by typing exit

8 . Finding postgresql.conf
`sudo find / -name "postgresql.conf" `

Or 
	`locate "postgresql.conf"`
	
9 . Then edit postgresql.conf
`sudo nano /etc/postgresql/12/main/postgresql.conf`

& add this line -
> listen_addresses = '*' 

10 . locate pg_hba.conf & add these 2 lines at the bottom(Make sure you maintain the spaces/tab with the top level)-
> host	all		all         0.0.0.0/0		md5
host	all		all		::/0		md5

11 . `sudo systemctl restart postgresql`