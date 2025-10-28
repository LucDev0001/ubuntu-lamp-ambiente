#!/bin/bash

# --- Verificação de Root ---
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, execute este script como root (com sudo)"
  exit 1
fi

echo "--- Iniciando a instalação do Ambiente LAMP para Ubuntu/Debian ---"

# --- Passo 1: Atualizar e Instalar Pacotes ---
echo "Atualizando pacotes..."
apt update

echo "Instalando Apache, MariaDB, PHP, Zenity e extensões..."
# Instala tudo de uma vez
apt install -y apache2 mariadb-server php libapache2-mod-php php-mysql \
               php-gd php-curl php-xml php-mbstring \
               zenity wget unzip

echo "Instalando PhpMyAdmin..."
# Força a reconfiguração para garantir que o Apache seja selecionado
echo "------ [ATENÇÃO] ------"
echo "Você precisará interagir com a instalação do PhpMyAdmin agora."
echo "1. Pressione 'OK'."
echo "2. Escolha 'Sim' para dbconfig-common (defina uma senha se pedir)."
echo "3. MAIS IMPORTANTE: Na tela 'Servidor web', pressione BARRA DE ESPAÇO para marcar 'apache2'."
echo "Pressione Enter para continuar..."
read # Pausa o script e espera o usuário pressionar Enter
dpkg-reconfigure phpmyadmin

# --- Passo 2: Criar o Script Gerenciador Gráfico ---
echo "Instalando script 'dev-lamp-manager'..."
# Usamos 'cat' para criar o arquivo diretamente no local correto
cat > /usr/local/bin/dev-lamp-manager << 'EOF'
#!/bin/bash

# 1. Obter o status atual dos serviços
STATUS_APACHE=$(systemctl is-active apache2)
STATUS_MARIADB=$(systemctl is-active mariadb)

# 2. Mostrar o menu principal com Zenity
ACTION=$(zenity --list --radiolist \
  --title="Gerenciador de Ambiente LAMP" \
  --text="Status atual:\n  Apache: <b>$STATUS_APACHE</b>\n  MariaDB: <b>$STATUS_MARIADB</b>" \
  --column="" --column="Ação" \
  TRUE "Iniciar Serviços" \
  FALSE "Parar Serviços" \
  FALSE "Ver Links de Acesso" \
  --height=270 --width=350)

# Se o usuário fechar a janela, $ACTION estará vazio
if [ -z "$ACTION" ]; then
    exit 0
fi

# 3. Executar a ação selecionada
case $ACTION in
  "Iniciar Serviços")
    (
    echo "10"
    echo "# Iniciando Apache2 (httpd)..."
    pkexec systemctl start apache2
    echo "50"
    echo "# Iniciando MariaDB (mysql)..."
    pkexec systemctl start mariadb
    echo "100"
    ) | zenity --progress --title="Iniciando" --text="Iniciando serviços..." --percentage=0 --auto-close --width=300
    
    zenity --info --width=300 --text="Serviços iniciados com sucesso!"
    ;;

  "Parar Serviços")
    (
    echo "10"
    echo "# Parando Apache2 (httpd)..."
    pkexec systemctl stop apache2
    echo "50"
    echo "# Parando MariaDB (mysql)..."
    pkexec systemctl stop mariadb
    echo "100"
    ) | zenity --progress --title="Parando" --text="Parando serviços..." --percentage=0 --auto-close --width=300

    zenity --info --width=300 --text="Serviços parados com sucesso!"
    ;;

  "Ver Links de Acesso")
    zenity --info --title="Links de Acesso" --width=400 \
    --text="Aqui estão seus links:\n\n• <b>Servidor Web:</b> http://localhost\n• <b>Admin do Banco:</b> http://localhost/phpmyadmin\n• <b>Gestor de Ficheiros:</b> http://localhost/filemanager.php"
    ;;
esac

exit 0
EOF

# Dar permissão de execução
chmod +x /usr/local/bin/dev-lamp-manager
echo "Script gerenciador instalado."

# --- Passo 3: Configurar Permissões do Apache ---
echo "Configurando permissões da pasta /var/www/html..."
# $SUDO_USER é o usuário que chamou o 'sudo', garantindo que o usuário certo seja adicionado
if [ -n "$SUDO_USER" ]; then
    usermod -a -G www-data $SUDO_USER
fi
chown -R www-data:www-data /var/www/html
chmod -R g+w /var/www/html

echo "Permissões configuradas."

# --- Passo 4: Instalar Gerenciador de Arquivos Simples ---
echo "Instalando Tiny File Manager..."
wget -O /var/www/html/filemanager.php https://raw.githubusercontent.com/prasathmani/tinyfilemanager/master/tinyfilemanager.php
chown www-data:www-data /var/www/html/filemanager.php

echo "--- INSTALAÇÃO QUASE CONCLUÍDA! ---"
echo ""
echo "Ações manuais obrigatórias:"
echo "1. SEGURANÇA DO BANCO: Execute 'sudo mysql_secure_installation' para definir uma senha root."
echo "2. LOGIN DO PHPMYADMIN: Para o root fazer login no PhpMyAdmin, execute:"
echo "   sudo mariadb -e \"ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'SUA_SENHA_AQUI';\""
echo "   (Troque 'SUA_SENHA_AQUI' pela senha que você definiu no passo 1)"
echo "3. SENHA DO GERENCIADOR: Edite o arquivo '/var/www/html/filemanager.php' e configure uma senha segura (procure por \$auth_users)."
echo "4. ÍCONE DO LANÇADOR: O script não instala o ícone gráfico. Veja o README.md para instruções."
echo "5. REINICIE: Você precisa SAIR DA SESSÃO (Logout/Login) para que as permissões do grupo www-data tenham efeito."
echo ""
echo "Fim."
