#### **Change Password in AWS EC2 linux server**
    sudo passwd username
    Enter new UNIX password:
    Retype new UNIX password:
    passwd: password updated successfully

#### **How to edit sshd_config remotely? A problem of incorrect permissions?**
1. `
sudo nano /etc/ssh/sshd_config
`

2. Change PasswordAuthentication & PermitEmptyPasswords in  sshd_config file like this-
```
PasswordAuthentication yes
PermitEmptyPasswords yes
```
3. Make your changes and press CTRL+O to save and CTRL+X to exit

4.  `
service sshd restart
`
5. You may need to put password in this case.

#### **How to make changes in the code remotely?**

1. Actually it is very easy. At first install [Visual Studio Code Insiders](https://code.visualstudio.com/insiders/ "here")

2. Inside VS Code Insider install the extension called [Remote - SSH](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh "Remote - SSH")

3. Select Remote explorer and click '+' icon. Paste the ssh key and your remote server password. After suscess you can able to access your server from VS Code.
	Note: If you have confusion you can watch 
	- This [Youtube Video Tutorial](https://youtu.be/JkbWXe-CjcA "Youtube video tutorial") for Connecting VSCode to AWS EC2 Instance



