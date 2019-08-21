#!/bin/bash

ARCH=amd64
APT_REQUIRED_PACKAGES='dirmngr unzip net-tools build-essential git gnupg zsh jq tmux vim'
APT_INSTALL_FLAGS='--install-recommends --assume-yes'
OP_VERSION=0.5.7
OP_SUBDOMAIN=my
OP_GNUPG_KEY=3FEF9748469ADBE15DA7CA80AC2D62742012EA22
OP_SSH_KEY_ITEM='lgkeqx3xzrfbcrkenn6otgg3oq'
BOOT_SSH_PRIVATE_KEY_FILE=~/.ssh/id_rsa
BOOT_SSH_PUBLIC_KEY_FILE=~/.ssh/id_rsa.pub

welcome_message() {
  cat << EOF
This program will setup this linux environment to a standard configuraiton.
As part of this setup process it will install the following packages;
- zsh
- oh-my-zsh
- git
- gnupg
- vim
- tmux
- build-essential (for make)
- jq

Additionally it will install standard dot files to support this configuration
that will override existing configuration for zsh, git, vim and tmux.

Please backup these files if required!

EOF
}

verify_intent() {
  while true; do
    read -p "Do you wish to continue?" yn
    case $yn in
      [Yy]* ) return 0;;
      [Nn]* ) exit 1;;
      * ) echo "Please answer yes or no.";;
    esac
  done
}

reset_user_password() {
  while true; do
    read -p "Do you know the password for account: $(whoami)? (Yes, No or Abort)" yn
    case $yn in
      [Yy]* ) return 0;;
      [Nn]* ) sudo passwd $(whoami); break;;
      [Aa]* ) exit 0;;
      *) echo "Please answer yes, no or abort.";;
    esac
  done
}

update_aptitude() {
  sudo apt-get update
  
  if [ "$?" -ne 0 ]; then
    echo "Unable to update aptitude! Check your network settings. Aborting!"
    exit 1
  fi
}

install_prerequisites() {
  sudo apt-get $APT_INSTALL_FLAGS install $APT_REQUIRED_PACKAGES
}

1password_obtain_gnupg_key() {
  gpg --receive-keys $OP_GNUPG_KEY
  if [ "$?" -ne 0 ]; then
    echo "Unable to obtain 1Password GNUPG keys for signature verification. Aborting!"
    exit 1
  fi
}

1password_verify_app_signature() {
  gpg --verify /tmp/op.sig /tmp/op

  if [ "$?" -ne 0 ]; then
    echo "Unable to verify application signauture!"
    exit 1
  fi

  rm /tmp/op.sig
  echo "1Password app signature verified..."
}

keymanager_configure() {
  1password_obtain_gnupg_key

  OP_ZIPFILE="/tmp/op_linux_${ARCH}_v${OP_VERSION}.zip"
  wget "https://cache.agilebits.com/dist/1P/op/pkg/v${OP_VERSION}/op_linux_${ARCH}_v${OP_VERSION}.zip" -O $OP_ZIPFILE

  if [ -f $OP_ZIPFILE ]; then
    unzip $OP_ZIPFILE -d /tmp
  else
    echo "Unable to find $OP_ZIPFILE"
    exit 1
  fi

  1password_verify_app_signature

  sudo mv /tmp/op /usr/local/bin
  sudo chown root:staff /usr/local/bin/op
  
  read -p "Provide 1Password username:" OP_USERNAME

  eval $(op signin $OP_USERNAME $OP_SUBDOMAIN)
}

keymanager_install_ssh_key_pair() {
  echo $OP_SESSION_my
  mkdir -p ~/.ssh
  if [ "$?" -ne 0 ]; then
    echo "Unable to initialize SSH key directory ~/.ssh . Aborting!"
    exit 1
  fi

  /bin/echo "$(op get item $OP_SSH_KEY_ITEM | jq -r '.details.password')" > $BOOT_SSH_PRIVATE_KEY_FILE
  chmod og-rwx ~/.ssh/id_rsa
  if [ "$?" -ne 0 ]; then
    echo "Unable to change permissions on private key. This will cause problems later."
  fi

  /bin/echo "$(op get item $OP_SSH_KEY_ITEM | jq -r '.details.sections[0].fields[0].v')" > $BOOT_SSH_PUBLIC_KEY_FILE
}

ohmyzsh_install() {
  sh -c "$(wget -O- https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)" "" --unattended

  if [ "$?" -ne 0 ]; then
    echo "Unable to install oh-my-zsh. Aborting!"
    exit 1;
  fi

  git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:=~/.oh-my-zsh/custom}/plugins/zsh-completions
  git clone https://github.com/zsh-users/zsh-autosuggestions.git $ZSH_CUSTOM/plugins/zsh-autosuggestions
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $ZSH_CUSTOM/plugins/zsh-syntax-highlighting
}

tmux_install_plugins() {
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
}

vim_install_plugins() {
  mkdir -p ~/.vim/colors
  wget https://www.vim.org/scripts/download_script.php\?src_id\=14937 -O ~/.vim/colors/twilight256.vim
  git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/plugin/Vundle.vim
}

dotfiles_install() {
  git clone git@github.com:samsoir/dotfiles.git ~/dotfiles

  make -C ~/dotfiles
}

complete_tasks() {
  vim +PluginInstall +qall

  echo "System bootstrapped!\n\n"
  echo "Remember to reload your zsh environment: source ~/.zshrc\n"
  echo "Remember to install tmux plugins within tmux: prefix + I\n"
  echo "Enjoy!\n"
  exit 0
}

# 1. Check intention of user
welcome_message
verify_intent

# 2. Ensure user knows their own credentials
reset_user_password

# 3. Install prerequisits
update_aptitude
install_prerequisites

# 4. Configure manager for SSH credentials and setup SSH keys
keymanager_configure
keymanager_install_ssh_key_pair 

# 5. Install oh-my-zsh
ohmyzsh_install

# 6. Install tmux plugins
tmux_install_plugins

# 7. Install vim plugins
vim_install_plugins

# 8. Setup environment
dotfiles_install

# 9. Tidy up
complete_tasks
