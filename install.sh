#!/bin/bash

# --- Configurações Visuais ---
TITLE="Titan LAMP Dashboard v3.0"
ICON="utilities-system-monitor" # Ícone do sistema (pode mudar para o seu)

# --- Verificação de Root ---
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, execute como root (sudo ./install.sh)"
  exit 1
fi

echo "--- INSTALANDO DEPENDÊNCIAS DO TITAN ---"
# Atualiza e instala YAD (Interface), dstat (stats) e curl
apt update
apt install -y apache2 mariadb-server php libapache2-mod-php php-mysql \
               php-gd php-curl php-xml php-mbstring \
               yad dstat curl unzip jq xterm

# --- Instalação do Ngrok (Se não existir) ---
if ! command -v ngrok &> /dev/null; then
    echo "Instalando Ngrok (Para acesso remoto)..."
    curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
    echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | tee /etc/apt/sources.list.d/ngrok.list
    apt update && apt install ngrok -y
fi

# --- Criando o Executável do Painel ---
echo "Criando o script do Dashboard..."

cat > /usr/local/bin/titan-lamp << 'EOF'
#!/bin/bash

# Variáveis
USER_NAME=$(logname)
TITLE="Titan LAMP - Olá, $USER_NAME"
ICON="network-server"

# Função de Loading (Visual Bonito)
loading() {
    (
    echo "10"; sleep 0.5
    echo "# $1"; echo "50"; sleep 0.5
    echo "100"
    ) | yad --progress --pulsate --title="Processando" --text="Aguarde..." --auto-close --no-cancel --width=300
}

# --- LÓGICA DO NGROK ---
toggle_ngrok() {
    if pgrep ngrok > /dev/null; then
        pkill ngrok
        yad --notification --image="network-offline" --text="Ngrok Desligado."
    else
        # Pede token se não tiver
        if [ ! -f /home/$USER_NAME/.ngrok2/ngrok.yml ] && [ ! -f /home/$USER_NAME/.config/ngrok/ngrok.yml ]; then
            TOKEN=$(yad --entry --title="Configurar Ngrok" --text="Cole seu Authtoken do ngrok.com:" --width=400)
            if [ ! -z "$TOKEN" ]; then
                sudo -u $USER_NAME ngrok config add-authtoken $TOKEN
            else
                return
            fi
        fi
        
        # Inicia Ngrok em background
        nohup sudo -u $USER_NAME ngrok http 80 > /dev/null 2>&1 &
        loading "Iniciando Túnel Seguro..."
        sleep 3
        
        # Pega a URL
        URL=$(curl -s localhost:4040/api/tunnels | grep -o "https://[a-zA-Z0-9-]*\.ngrok-free\.app")
        
        if [ ! -z "$URL" ]; then
            yad --entry --title="SUCESSO! SEU LINK PÚBLICO" --text="Copie e compartilhe este link:" --entry-text="$URL" --width=500 --button="Abrir Link":0 --button="OK":1
            if [ $? -eq 0 ]; then xdg-open "$URL"; fi
        else
            yad --error --text="Falha ao iniciar Ngrok. Verifique seu token."
        fi
    fi
}

# --- FERRAMENTA DE SENHA ---
change_pass() {
    NOVA=$(yad --entry --title="Alterar Senha FileMgr" --text="Digite a nova senha:" --hide-text)
    if [ ! -z "$NOVA" ]; then
        HASH=$(php -r "echo password_hash('$NOVA', PASSWORD_DEFAULT);")
        # Mostra o hash para o usuário copiar (edição automática é arriscada com regex em PHP complexo)
        yad --form --title="Atualizar Senha" \
        --text="O TinyFileManager usa hash seguro. \n1. Copie o código abaixo.\n2. O arquivo de configuração abrirá.\n3. Cole no lugar da senha antiga." \
        --field="Hash (Copie isso):RO" "$HASH" \
        --width=600
        
        xdg-open /var/www/html/filemanager.php
    fi
}

# --- LOOP PRINCIPAL DO DASHBOARD ---
while true; do
    # Verifica Status
    if systemctl is-active --quiet apache2; then S_AP="✅ ONLINE"; else S_AP="🔴 OFF"; fi
    if systemctl is-active --quiet mariadb; then S_DB="✅ ONLINE"; else S_DB="🔴 OFF"; fi
    if pgrep ngrok > /dev/null; then S_NG="☁️ ONLINE"; else S_NG="⚪ OFF"; fi

    # Verifica Recursos (Simples)
    MEM=$(free -h | grep Mem | awk '{print $3 "/" $2}')
    CPU=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')

    # JANELA PRINCIPAL (NOTEBOOK/ABAS)
    ACTION=$(yad --notebook --title="$TITLE" --window-icon="$ICON" --width=700 --height=500 \
    --key=12345 --tab="🚀 Controle" --tab="🌍 Remoto (Ngrok)" --tab="📊 Monitor" --tab="🛠️ Ferramentas" \
    \
    --tab-content="
    <span size='x-large' weight='bold'>Controle de Serviços</span>
    
    Status Apache:  <b>$S_AP</b>
    Status MariaDB: <b>$S_DB</b>
    
    <span color='gray'>Gerencie o servidor local:</span>
    " \
    --button="▶️ Iniciar Tudo!bash -c 'echo START'":0 \
    --button="⏹️ Parar Tudo!bash -c 'echo STOP'":0 \
    --button="🔄 Reiniciar!bash -c 'echo RESTART'":0 \
    --button="🌐 Criar Site (.test)!bash -c 'echo VHOST'":0 \
    --button="Sair!quit":1 \
    \
    --tab-content="
    <span size='x-large' weight='bold' color='#6435eb'>Acesso Remoto (Ngrok)</span>
    
    Status do Túnel: <b>$S_NG</b>
    
    Use isso para mostrar seu localhost para clientes ou amigos via internet.
    " \
    --button="🔗 Ligar/Desligar Link Público!bash -c 'echo NGROK'":0 \
    \
    --tab-content="
    <span size='x-large'>Estatísticas do Sistema</span>
    
    <b>Memória RAM:</b> $MEM
    <b>Uso de CPU:</b> $CPU
    
    <i>(Valores atualizados ao recarregar o painel)</i>
    " \
    --button="Atualizar Stats!bash -c 'echo REFRESH'":0 \
    \
    --tab-content="
    <span size='x-large'>Ferramentas Avançadas</span>
    " \
    --button="📂 Gerenciador Arq!bash -c 'echo FILES'":0 \
    --button="🛢️ PhpMyAdmin!bash -c 'echo ADMIN'":0 \
    --button="📜 Ver Logs (Ao Vivo)!bash -c 'echo LOGS'":0 \
    --button="🔑 Mudar Senha Arq!bash -c 'echo PASS'":0 \
    )

    RET=$?
    # Trata a saída do YAD (ele retorna a string do botão clicado)
    # Remove o trash do output do yad se houver
    CMD=$(echo $ACTION | awk -F'|' '{print $1}')

    if [ $RET -ne 0 ]; then break; fi # Fechou a janela

    case $CMD in
        START)
            pkexec bash -c "systemctl start apache2 && systemctl start mariadb"
            loading "Iniciando motores..."
            ;;
        STOP)
            pkexec bash -c "systemctl stop apache2 && systemctl stop mariadb"
            loading "Desligando tudo..."
            ;;
        RESTART)
            pkexec bash -c "systemctl restart apache2 && systemctl restart mariadb"
            loading "Reiniciando..."
            ;;
        NGROK)
            toggle_ngrok
            ;;
        VHOST)
            NOME=$(yad --entry --title="Novo Site" --text="Nome do site (ex: portfolio):")
            if [ ! -z "$NOME" ]; then
                CMD_VHOST="mkdir -p /var/www/html/$NOME && \
                echo '<VirtualHost *:80>' > /etc/apache2/sites-available/$NOME.conf && \
                echo '    ServerName $NOME.test' >> /etc/apache2/sites-available/$NOME.conf && \
                echo '    DocumentRoot /var/www/html/$NOME' >> /etc/apache2/sites-available/$NOME.conf && \
                echo '</VirtualHost>' >> /etc/apache2/sites-available/$NOME.conf && \
                echo '127.0.0.1 $NOME.test' >> /etc/hosts && \
                a2ensite $NOME.conf && systemctl reload apache2 && \
                chown -R $USER:$USER /var/www/html/$NOME && \
                echo '<h1>$NOME Criado com Sucesso!</h1>' > /var/www/html/$NOME/index.php"
                
                pkexec bash -c "$CMD_VHOST"
                loading "Configurando DNS e Apache..."
                yad --info --text="Site criado: http://$NOME.test"
            fi
            ;;
        LOGS)
            # Abre logs em janela separada bonita do YAD
            xterm -geometry 120x30 -title "Logs do Apache (Erros)" -e "tail -f /var/log/apache2/error.log" &
            ;;
        FILES) xdg-open "http://localhost/filemanager.php" ;;
        ADMIN) xdg-open "http://localhost/phpmyadmin" ;;
        PASS) change_pass ;;
        REFRESH) continue ;;
    esac
done
EOF

chmod +x /usr/local/bin/titan-lamp

# --- Ícone e Menu ---
echo "Configurando ícone..."
ICON_DIR="/usr/share/icons/hicolor/128x128/apps"
mkdir -p $ICON_DIR
wget -q -O $ICON_DIR/titan-lamp.png https://cdn-icons-png.flaticon.com/512/9662/9662360.png

cat > /usr/share/applications/titan-lamp.desktop << EOF
[Desktop Entry]
Version=1.0
Name=Titan Dashboard
Comment=Gerencie seu servidor Web
Exec=/usr/local/bin/titan-lamp
Icon=titan-lamp
Terminal=false
Type=Application
Categories=Development;
EOF

echo ""
echo "--- INSTALAÇÃO TITAN CONCLUÍDA! ---"
echo "Procure por 'Titan Dashboard' no seu menu."