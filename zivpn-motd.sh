#!/bin/bash

clear
# Check for lolcat
if command -v lolcat &> /dev/null; then
  LOLCAT="lolcat"
  else
  LOLCAT="cat"
fi

# Check for figlet
if command -v figlet &> /dev/null; then
  FIGLET="figlet -f slant"
  else
  FIGLET="echo"
fi

# Define Colors
WHITE='\033[1;37m'
NC='\033[0m'
YELLOW='\033[1;33m'

# Display Welcome Message
clear
$FIGLET "ZIVPN" | $LOLCAT
echo -e "============================================" | $LOLCAT
echo -e "      Selamat Datang di ZIVPN Manager       " | $LOLCAT
echo -e "============================================" | $LOLCAT
echo -e "${WHITE}Ketik '${YELLOW}zivpn${WHITE}' untuk membuka menu panel.${NC}"
echo ""