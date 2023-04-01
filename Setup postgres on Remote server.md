## Setting Up Postgre on remote server
* To install PostgreSQL, first refresh your server’s local package index: `sudo apt update`

*  `sudo apt install postgresql postgresql-contrib -y`

*  `sudo systemctl start postgresql.service`

*  `sudo su postgres`

*  `psql -U  postgres -c "CREATE ROLE ubuntu;"`

*  `psql -U  postgres -c "ALTER ROLE ubuntu WITH LOGIN;"`

*  ` psql -U  postgres -c "ALTER ROLE ubuntu CREATEDB;"`

*  `psql -U  postgres -c "ALTER ROLE ubuntu WITH PASSWORD '1234';"`

*  Then exit from psql by typing `exit`

*  Finding postgresql.conf `sudo find / -name "postgresql.conf" `
Or 	`locate "postgresql.conf"`
	
*  Then edit postgresql.conf `sudo nano /etc/postgresql/12/main/postgresql.conf`

	& add this line -
	> listen_addresses = '*' 

*  locate pg_hba.conf & add these 2 lines at the bottom(Make sure you maintain the spaces/tab with the top level)-
> host	all		all         0.0.0.0/0		md5
> host	all		all		::/0		md5

*  `sudo systemctl restart postgresql`

*  If firewall is enabled then make sure the port is allowed. To allow port 5432 ->
`ufw allow 5438`