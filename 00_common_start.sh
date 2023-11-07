#!/bin/bash
# source pi8.odoo.sh
# Definir códigos de color como constantes
VERSION="0.55"
GREEN_BR="\033[38;2;0;255;0m"
GREEN="\033[32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
NC="\e[0m"
NC_BR="\e[97m"


# Función para registrar el inicio de un paso
function log_start {
    local STEP=$1
    local MESSAGE=$2
    echo -e "${GREEN_BR}Paso ${STEP}: ${MESSAGE} - Iniciando...${NC}"
}

# Función para registrar el final de un paso
function log_end {
    local STEP=$1
    local MESSAGE=$2
    echo -e "${GREEN_BR}Paso ${STEP}: ${MESSAGE} - Completado.${NC}"
    echo "---------------------------------------------------"  # Separador de puntos
    echo ""  # Espacio en blanco
}

# Función para registrar un error y opcionalmente terminar el script
function log_end_error {
    local STEP=$1
    local MESSAGE=$2
    local SHOULD_EXIT=${3:-1}  # Establecer a 1 por defecto si no se proporciona un tercer argumento

    echo -e "${RED}Paso ${STEP}: ${MESSAGE} - Error.${COLOR_RESET}"
    
    if [ "$SHOULD_EXIT" -eq 1 ]; then
        echo -e "${RED}Deteniendo el script.${COLOR_RESET}"
        exit 1  # Salir del script con un código de error
    else
        echo -e "${YELLOW}Continuando con el script...${COLOR_RESET}"
    fi
}

# Método para mostrar mensajes informativos
function log_info() {
    local message="$1"
    echo -e "${YELLOW}INFO: $message${NC}"
}

function log_ask_user() {
    local prompt="$1"
    local response

    # Pregunta en color verde
    echo -e "${GREEN}${prompt} (s/n): ${NC}"
    read -r response

    if [[ "$response" =~ ^[SsYy]$ ]]; then
        return 0  # Retorna 0 para indicar "sí"
    else
        return 1  # Retorna 1 para indicar "no"
    fi
}

# Pregunta al usuario y retorna una cadena de caracteres
function log_ask() {
    local prompt="$1"
    local response

    # Pregunta en color verde
    echo -e "${GREEN}${prompt}: ${NC}"
}

# ******* Funciones de Configuración  - - - - - - - - - *******
# Variables para almacenar valores globales
function step01_actualizacion_de_paquetes {
    log_start "01" "Actualización Inicial de Paquetes"
    
    sudo apt-get update
    if [ $? -eq 0 ]; then
        log_end "01" "Actualización de paquetes completada con éxito."
    else
        log_end_error "01" "Hubo un error durante la actualización de paquetes." 0
    fi
     sudo sudo apt upgrade

}

function step02_instalacion_librerias_base {
    log_start "02" "Instalación de Librerías Base"
    
    sudo apt-get install -y git net-tools curl
    if [ $? -eq 0 ]; then
        log_end "02" "Librerías base instaladas con éxito."
    else
        log_end_error "02" "Hubo un error durante la instalación de las librerías base."
    fi
}

# Cambio de contraseña de root
function step03_cambia_contrasena_root {
    log_start "03" "Cambio de Contraseña para ROOT"

    # Pregunta por la contraseña usando log_ask_string
    log_ask "Por favor introduce la nueva contraseña para ROOT"
    read -r ROOT_PASSWORD
    
    # Usa la variable local ROOT_PASSWORD para cambiar la contraseña
    echo -e "$ROOT_PASSWORD\n$ROOT_PASSWORD" | sudo passwd root

    # Verifica el estado del último comando ejecutado
    if [ $? -eq 0 ]; then
        log_end "03" "Contraseña de ROOT cambiada con éxito."
    else
        log_end_error "03" "Hubo un error al cambiar la contraseña de ROOT."
    fi
}

function step04_configurar_nobloqueo() {
    log_start "04" "Configurando opciones para evitar el bloqueo"

    # 1. Evitar desconexiones SSH desde el cliente
    log_info "Configurando SSH para evitar desconexiones en el lado del cliente..."
    mkdir -p ~/.ssh
    echo -e "Host *\nServerAliveInterval 60" >> ~/.ssh/config
    chmod 600 ~/.ssh/config

    # 2. Evitar desconexiones SSH desde el servidor (necesitas privilegios de root para esto)
    if [ "$EUID" -ne 0 ]; then
        log_info "Por favor, ejecuta este script como root para configurar el servidor SSH."
        log_end_error "04" "No se pudo configurar el servidor SSH porque el script no se ejecutó como root."
        return
    else
        log_info "Configurando SSH para evitar desconexiones en el lado del servidor..."
        echo -e "\nClientAliveInterval 60\nClientAliveCountMax 1000" >> /etc/ssh/sshd_config
        service ssh restart || log_end_error "04" "Fallo al reiniciar el servicio SSH."
    fi

    # 3. Configuración de energía y bloqueo de pantalla (específico para GNOME)
    if hash gsettings 2>/dev/null; then
        log_info "Configurando opciones de energía y bloqueo de pantalla para GNOME..."
        gsettings set org.gnome.desktop.session idle-delay 0
        gsettings set org.gnome.desktop.screensaver lock-enabled false
    else
        log_info "No se encontró 'gsettings'. Omitiendo la configuración de GNOME."
    fi

    log_end "04" "Configuración completa. Por favor, revisa las opciones y asegúrate de que todo esté como lo deseas."
}

function step05_generar_ssh_genkeys() {
    log_start "05" "Generación y Muestra de Claves SSH"

    # Mostrar advertencia
    log_info "¡ADVERTENCIA!"
    log_info "La generación de claves SSH sobrescribirá las claves existentes, si las hay."
    log_info "Si continúas, las claves actuales se perderán permanentemente."

    # Preguntar al usuario si desea continuar
    if log_ask_user "¿Deseas continuar?"; then
        log_info "Generando claves SSH..."

        ssh-keygen -t rsa -b 4096 -C "$SSH_KEYGEN_EMAIL"

        if [ $? -eq 0 ]; then
            log_info "Claves SSH generadas."
            
            log_info "Mostrando clave pública SSH..."
            cat ~/.ssh/id_rsa.pub
            read -p "Presiona cualquier tecla para continuar..."
            
            log_end "05" "Generación y Muestra de Claves SSH completadas con éxito"
        else
            log_error "05" "Falló la generación de claves SSH. Por favor, verifica y soluciona el problema."
        fi
    else
        log_end "05" "Generación y Muestra de Claves SSH canceladas por el usuario"
    fi
}

# Clonado de repositorio.
function setup09_clone_repository() {
    log_start "09" "Iniciando la clonación del repositorio"

    # Define las variables de directorio
    BIN_DIRECTORY="/usr/local/bin"
    GITREPO_DIRECTORY="/usr/local/bin/pi8.server"
    GITREPO_SSH="git@github.com:rigocalop/pi8.server.git"  # Ruta por defecto del repositorio

    # Elimina el directorio del repositorio si ya existe
    if [[ -d "$GITREPO_DIRECTORY" ]]; then
        log_info "Eliminando directorio del repositorio existente..."
        rm -rf "$GITREPO_DIRECTORY" || log_end_error "09" "Error al eliminar el directorio existente"
    fi

    # Clona el repositorio
    log_info "Clonando repositorio..."
    git clone "$GITREPO_SSH" "$GITREPO_DIRECTORY" || log_end_error "09" "Error al clonar el repositorio"

    # Lista el directorio clonado
    ls -al "$GITREPO_DIRECTORY" || log_end_error "09" "Error al listar el directorio clonado"

    # Copia el contenido del repositorio al directorio /usr/local/bin
    log_info "Copiando archivos al directorio bin..."
    cp -rf "$GITREPO_DIRECTORY"/* "$BIN_DIRECTORY/" || log_end_error "09" "Error al copiar los archivos"

    # Cambia el nombre y los permisos del script
    log_info "Configurando el script..."
    chmod +x "$BIN_DIRECTORY/pi8.server.sh" || log_end_error "09" "Error al hacer el script ejecutable"
    chmod +x "$BIN_DIRECTORY/pi8.wireguard.sh" || log_end_error "09" "Error al hacer el script ejecutable"
    chmod +x "$BIN_DIRECTORY/pi8.odoo.sh" || log_end_error "09" "Error al hacer el script ejecutable"

    log_end "09" "Clonación y configuración del repositorio completadas"
}

#******* Funciones de Opciones Adicionales - INSTALAR - *******
# Función para instalar Nginx
function addopt11_nginx() {
    if log_ask_user "¿Desea instalar Nginx?"; then
        log_start "11" "Instalación de Nginx"

        if [ -x "$(command -v nginx)" ]; then
            log_info "Nginx ya está instalado en el sistema."
        else
            if dpkg -l apache2 > /dev/null 2>&1; then
                log_info "Apache está instalado en el sistema."
                if sudo service apache2 status > /dev/null 2>&1; then
                    log_info "Deteniendo Apache..."
                    sudo service apache2 stop || log_end_error "11" "Error al detener Apache"
                fi
                log_info "Desinstalando Apache..."
                sudo apt-get remove --purge apache2 || log_end_error "11" "Error al desinstalar Apache"
                sudo apt-get autoremove || log_end_error "11" "Error al desinstalar Apache"
            fi

            sudo apt update || log_end_error "11" "Error al actualizar la lista de paquetes"
            sudo apt install -y nginx || log_end_error "11" "Error al instalar Nginx"

            if [ ! -x "$(command -v nginx)" ]; then
                log_end_error "11" "Error durante la instalación de Nginx"
            fi
        fi

        sudo systemctl enable nginx || log_end_error "11" "Error al habilitar Nginx en el inicio"

        if ! sudo systemctl is-active --quiet nginx; then
            sudo systemctl start nginx || log_end_error "11" "Error al iniciar Nginx"
        fi

        if sudo systemctl is-active --quiet nginx; then
            log_info "Nginx está funcionando"
        else
            log_end_error "11" "Nginx no está funcionando"
        fi

        log_end "11" "Instalación de Nginx completada"
    else
        log_info "Saltando la instalación de Nginx..."
    fi
}

# Función para instalar Certbot
function addopt12_certbot() {
    if log_ask_user "¿Desea instalar Certbot para la gestión de certificados SSL?"; then
        log_start "12" "Iniciando la instalación de Certbot"

        # Actualizar repositorios
        sudo apt-get update

        # Instalar software-properties-common si no está instalado
        if [ ! -x "$(command -v add-apt-repository)" ]; then
            sudo apt-get install -y software-properties-common
        fi

        # Agregar el repositorio de Certbot
        sudo add-apt-repository -y ppa:certbot/certbot

        # Actualizar la base de datos de paquetes con los nuevos repositorios
        sudo apt-get update

        # Instalar Certbot
        sudo apt-get install -y certbot python3-certbot-nginx

        # Verificar que Certbot se haya instalado correctamente
        if [ -x "$(command -v certbot)" ]; then
            log_end "12" "Certbot se ha instalado correctamente."
        else
            log_error "12" "Falló la instalación de Certbot. Por favor, verifica y soluciona el problema."
        fi
    else
        log_end "12" "Instalación de Certbot cancelada por el usuario."
    fi
}

# Función para instalar Docker
function addopt13_docker() {
    if log_ask_user "¿Desea instalar Docker?"; then
        log_start "13" "Iniciando la instalación de Docker"

        # Resto del código para instalar Docker
        sudo apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io

        # Verificar que Docker esté instalado correctamente
        if [ -x "$(command -v docker)" ]; then
            log_end "13" "Docker se ha instalado correctamente."
        else
            log_error "13" "Falló la instalación de Docker. Por favor, verifica y soluciona el problema."
        fi
    else
        log_end "13" "Instalación de Docker cancelada por el usuario."
    fi
}

# Función para instalar Docker Compose
function addopt14_docker_compose() {
    if log_ask_user "¿Desea instalar Docker Compose?"; then
        log_start "14" "Iniciando la instalación de Docker Compose"

        # Obtener la última versión de Docker Compose
        COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        
        # Descargar e instalar Docker Compose
        sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        
        # Dar permisos de ejecución al archivo binario
        sudo chmod +x /usr/local/bin/docker-compose

        # Verificar que Docker Compose esté instalado correctamente
        if [ -x "$(command -v docker-compose)" ]; then
            log_end "14" "Docker Compose se ha instalado correctamente."
        else
            log_error "14" "Falló la instalación de Docker Compose. Por favor, verifica y soluciona el problema."
        fi
    else
        log_end "14" "Instalación de Docker Compose cancelada por el usuario."
    fi
}

# Función para instalar Portainer
function addopt15_docker_portainer() {
    if log_ask_user "¿Desea instalar Portainer?"; then
        log_start "15" "Iniciando la instalación de Portainer"

        # Crear un volumen para Portainer
        sudo docker volume create portainer_data

        # Ejecutar un contenedor de Portainer
        sudo docker run -d -p 9000:9000 -p 8000:8000 --name=portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce

        # Verificar que Portainer esté corriendo
        if [ $(sudo docker ps -f "name=portainer" --format "{{.Names}}") == 'portainer' ]; then
            log_end "15" "Portainer se ha instalado y está corriendo correctamente."
        else
            log_error "15" "Falló la instalación o el inicio de Portainer. Por favor, verifica y soluciona el problema."
        fi
    else
        log_end "15" "Instalación de Portainer cancelada por el usuario."
    fi
}


#******* Funciones de Opciones Adicionales - DESINSTALAR *******
# Método para desinstalar Nginx
function revert11_nginx() {
    if log_ask_user "Estás a punto de desinstalar Nginx. ¿Deseas continuar?"; then
        log_start "11" "Deteniendo el servicio Nginx"

        sudo systemctl stop nginx
        if [ $? -ne 0 ]; then
            log_error "11" "Falló al detener el servicio Nginx. Por favor, verifica y soluciona el problema."
        fi

        log_start "11" "Desinstalando Nginx"

        sudo apt-get remove --purge nginx nginx-common nginx-full nginx-core -y
        sudo apt-get autoremove -y
        sudo apt-get autoclean

        if [ $? -eq 0 ]; then
            log_end "11" "Nginx ha sido desinstalado con éxito."
        else
            log_error "11" "Falló la desinstalación de Nginx. Por favor, verifica y soluciona el problema."
        fi
    else
        log_end "11" "Operación cancelada. Nginx no se desinstaló."
    fi
}

# Tu función revert12_certbot actualizada
function revert12_certbot() {
    if log_ask_user "Estás a punto de desinstalar Certbot. ¿Deseas continuar?"; then
        log_start "12" "Desinstalar Certbot..."

        sudo apt-get remove --purge certbot python3-certbot-nginx -y
        if [ $? -ne 0 ]; then
            log_error "12" "Hubo un error al desinstalar Certbot."
        fi

        sudo apt-get autoremove -y
        sudo apt-get autoclean

        log_end "12" "Certbot ha sido desinstalado."
    else
        log_end "12" "Operación cancelada. Certbot no se desinstaló."
    fi
}

# Menu para las funciones de revert
function revert13_docker() {
    if log_ask_user "¿Desea desinstalar Docker?"; then
        log_start "13" "Iniciando la desinstalación de Docker"
        
        echo "Desinstalando Docker de Ubuntu..."
        sudo apt-get remove --purge docker-engine docker docker.io docker-ce docker-ce-cli
        sudo apt-get autoremove -y
        sudo rm -rf /etc/systemd/system/docker.service.d
        sudo systemctl daemon-reload
        echo "Docker ha sido desinstalado de Ubuntu."

        log_end "13" "Docker se ha desinstalado correctamente."
    else
        log_end "13" "Desinstalación de Docker cancelada por el usuario."
    fi
}

# Función para desinstalar Docker Compose
function revert14_docker_compose() {
    if log_ask_user "¿Desea desinstalar Docker Compose?"; then
        log_start "15" "Iniciando la desinstalación de Docker Compose"

        # Eliminar el ejecutable de Docker Compose
        sudo rm /usr/local/bin/docker-compose

        # Verificar que Docker Compose se ha desinstalado correctamente
        if [ -x "$(command -v docker-compose)" ]; then
            log_error "15" "Falló la desinstalación de Docker Compose. Por favor, verifica y soluciona el problema."
        else
            log_end "15" "Docker Compose se ha desinstalado correctamente."
        fi
    else
        log_end "15" "Desinstalación de Docker Compose cancelada por el usuario."
    fi
}


# Función para desinstalar Portainer
function revert15_docker_portainer() {
    if log_ask_user "¿Desea desinstalar Portainer?"; then
        log_start "16" "Iniciando la desinstalación de Portainer"

        # Detener el contenedor de Portainer
        sudo docker stop portainer

        # Eliminar el contenedor de Portainer
        sudo docker rm portainer

        # Eliminar el volumen de Portainer
        sudo docker volume rm portainer_data

        # Verificar que Portainer se ha eliminado correctamente
        if [ -z $(sudo docker ps -a -f "name=portainer" --format "{{.Names}}") ]; then
            log_end "16" "Portainer se ha desinstalado correctamente."
        else
            log_error "16" "Falló la desinstalación de Portainer. Por favor, verifica y soluciona el problema."
        fi
    else
        log_end "16" "Desinstalación de Portainer cancelada por el usuario."
    fi
}

# Separadores
SEPARATOR="${GREEN_BR}============================================${NC}"
SEPARATOR_SIMPLE="${GREEN_BR}-------------------------------------------${NC}"

# Función principal del menú
function main_menu {
    #clear
    echo -e "$SEPARATOR"
    echo -e "${GREEN_BR}          MENU PRINCIPAL ${VERSION}:${NC}"
    echo -e "$SEPARATOR"
    echo -e "1) ${NC_BR}Pasos de Configuración Inicial (step)${NC}"
    echo -e "2) ${NC_BR}Opciones Adicionales (addopt)${NC}"
    echo -e "3) ${NC_BR}Revertir Configuraciones (revert)${NC}"
    echo -e "$SEPARATOR_SIMPLE"
    echo -e "9) ${NC_BR}Clonar Repositorio pi8.server${NC}"
    echo -e "0) ${NC_BR}Salir${NC}"
    echo -e "$SEPARATOR_SIMPLE"
    echo -e "30) ${NC_BR}Instalar Odoo.16.CE ${NC}"
    echo -e "31) ${NC_BR}Remover  Odoo.16.CE ${NC}"
    read -r -p "Elige una opción: " main_choice
    SEPARATOR_SIMPLE="${GREEN_BR}-------------------------------------------${NC}"
    case $main_choice in
        1) step_menu ;;
        2) addopt_menu ;;
        3) revert_menu ;;
        9) setup09_clone_repository ;;
        30) pi8_odoo_main ;;
        31) pi8_odoo_remove ;;
        0) exit 0 ;;
        *) echo -e "${NC_BR}Opción no válida.${NC}" ;;
    esac
}

# Menú para las funciones de step
function step_menu {
    #clear
    echo -e "$SEPARATOR"
    echo -e "${GREEN_BR} --  Configuraciones Básicas  -- ${NC}"
    echo -e "$SEPARATOR"
    echo -e "1) ${NC_BR}Actualización de Paquetes${NC}"
    echo -e "2) ${NC_BR}Instalaciòn de paquetes básicos${NC}"
    echo -e "3) ${NC_BR}Cambio de Contraseña Root${NC}"
    echo -e "4) ${NC_BR}Configurar No Bloqueo${NC}"
    echo -e "5) ${NC_BR}Configurar ssh keys${NC}"
    echo -e "$SEPARATOR_SIMPLE"

    echo -e "8) ${NC_BR}Ejecutar Todas las Opciones${NC}"
    echo -e "0) ${NC_BR}Volver al Menú Principal${NC}"
    echo -e "$SEPARATOR_SIMPLE"    
    read -r -p "Elige una opción: " step_choice
    case $step_choice in
        1) step01_actualizacion_de_paquetes && step_menu ;;
        2) step02_instalacion_librerias_base && step_menu ;;
        3) step03_cambia_contrasena_root && step_menu ;;
        4) step04_configurar_nobloqueo && step_menu ;;
        5) step05_generar_ssh_genkeys && step_menu ;;
        8) 
            step01_actualizacion_de_paquetes
            step02_instalacion_librerias_base
            step03_cambia_contrasena_root
            step04_configurar_nobloqueo
            step05_generar_ssh_genkeys
            step_menu
        ;;
        0) main_menu ;;
        *) echo -e "${RED}Opción no válida.${NC}"  && step_menu ;;
    esac
}

# Menú para las funciones de addopt
function addopt_menu {
    #clear
    echo -e "$SEPARATOR"
    echo -e "${GREEN_BR} --  Instalar Herramientas -- ${NC}"
    echo -e "$SEPARATOR"
    echo -e "1) ${NC_BR}Instalar Nginx${NC}"
    echo -e "2) ${NC_BR}Instalar Certbot${NC}"
    echo -e "3) ${NC_BR}Instalar Docker${NC}"
    echo -e "4) ${NC_BR}Instalar Docker-Compose${NC}"
    echo -e "5) ${NC_BR}Instalar Docker-Portainer${NC}"
    echo -e "$SEPARATOR_SIMPLE"
    echo -e "8) ${NC_BR}Ejecutar Todas las Opciones${NC}"
    echo -e "0) ${NC_BR}Volver al Menú Principal${NC}"
    echo -e "$SEPARATOR_SIMPLE"    
    read -r -p "Elige una opción: " addopt_choice

    case $addopt_choice in
        1) addopt11_nginx && addopt_menu ;;
        2) addopt12_certbot && addopt_menu ;;
        3) addopt13_docker && addopt_menu ;;
        4) addopt14_docker_compose && addopt_menu ;;
        5) addopt15_docker_portainer && addopt_menu ;;
        8)
            addopt11_nginx
            addopt12_certbot
            addopt13_docker
            addopt14_docker_compose
            addopt15_docker_portainer
            addopt_menu
        ;;
        0) main_menu ;;
        *) echo -e "${NC_BR}Opción no válida.${NC}" && addopt_menu ;;
    esac
}

# Menú para las funciones de revert
function revert_menu {
    #clear
    echo -e "$SEPARATOR"
    echo -e "${GREEN_BR} --  DesInstalar Herramientas -- ${NC}"
    echo -e "$SEPARATOR"
    echo -e "1) ${NC_BR}DesInstalar Nginx${NC}"
    echo -e "2) ${NC_BR}DesInstalar Certbot${NC}"
    echo -e "3) ${NC_BR}DesInstalar Docker${NC}"
    echo -e "4) ${NC_BR}DesInstalar Docker-Compose${NC}"
    echo -e "5) ${NC_BR}DesInstalar Docker-Portainer${NC}"

    echo -e "30) ${NC_BR}Instalar Odoo.16.CE ${NC}"
    echo -e "31) ${NC_BR}Remover  Odoo.16.CE ${NC}"
    
    echo -e "$SEPARATOR_SIMPLE"
    echo -e "8) ${NC_BR}Ejecutar Todas las Opciones${NC}"
    echo -e "0) ${NC_BR}Volver al Menú Principal${NC}"
    echo -e "$SEPARATOR_SIMPLE"    
    read -r -p "Elige una opción: " revert_choice

    case $revert_choice in
        1) revert11_nginx && revert_menu ;;
        2) revert12_certbot && revert_menu ;;
        3) revert13_docker && revert_menu ;;
        4) revert14_docker_compose && revert_menu ;;
        5) revert15_docker_portainer && revert_menu ;;
        8)
            revert11_nginx
            revert12_certbot
            revert13_docker
            revert14_docker_compose
            revert15_docker_portainer
            revert_menu
        ;;
        30) pi8_odoo_main ;;
        31) pi8_odoo_remove ;;
        0) main_menu ;;
        *) echo -e "${NC_BR}Opción no válida.${NC}" && revert_menu;;
    esac
}

# Aquí puedes añadir las definiciones de las funciones como step00_configuracion_inicial, addopt11_nginx, etc.

# Mostrar el menú principal al inicio
while true; do
    main_menu
done