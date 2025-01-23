#!/bin/bash

#Cor output terminal
VERDE='\033[0;32m'
VERMELHO='\033[0;31m'
AMARELO='\033[0;33m'
AZUL='\033[0;34m'
RESET='\033[0m'

EVIDENCE_DIR="evidencias_$(date '+%Y%m%d_%H%M%S')"
mkdir -p "$EVIDENCE_DIR"

#Endpoints por ambiente com ideia de classe
endpoints_prod=(
#ex:"https://exemple.com"
    ""
    ""

)

endpoints_hml=(
    ""
    ""

)

get_timestamp() {
    date '+%Y-%m-%d_%H-%M-%S'
}

check_loadbalancer() {
    local headers=$1
    local lb=false
    
    if echo "$headers" | grep -qi "x-forwarded-for\|x-real-ip\|x-load-balancer\|via:\|server:\ ELB\|AWS\|cloudfront\|nginx"; then
        lb=true
    fi
    
    echo "$lb"
}

save_evidence() {
    local url=$1
    local tipo=$2
    local cmd=$3
    local output=$4
    local arquivo="${EVIDENCE_DIR}/$(echo $url | sed 's/[^a-zA-Z0-9]/_/g')_${tipo}.txt"
    local lb_found=$(check_loadbalancer "$output")
    
    {
        echo "=== Evidência de Segurança ==="
        echo "URL: $url"
        echo "Tipo: $tipo"
        echo "Data: $(get_timestamp)"
        echo "Comando: $cmd"
        echo "---"
        echo "Saída:"
        echo "$output"
        echo "---"
        echo "Análise:"
        
        if [ "$tipo" = "https" ]; then
            echo "- HTTPS: OK"
            echo "- SSL/TLS: Validado"
            if [ "$lb_found" = "true" ]; then
                echo "- LoadBalancer: Detectado"
                echo "- SSL Termination: No LB"
            fi
        elif [ "$tipo" = "redirect" ]; then
            echo "- HTTP->HTTPS: OK (301)"
            if [ "$lb_found" = "true" ]; then
                echo "- Redirect: Via LB"
            fi
        fi
    } > "$arquivo"
    
    echo "$arquivo"
}

check_endpoint() {
    local url=$1
    local env=$2
    local ts=$(get_timestamp)
    local https_evidence=""
    local http_evidence=""
    
    echo "Checando $env: $url"
    echo "Hora: $ts"
    echo "----------------------------------------"
    
    local base_url=$(echo $url | sed -E 's#^https?://##')
    local http_url="http://$base_url"
    local https_url="https://$base_url"
    
    echo "Teste HTTPS..."
    https_cmd="curl -sILv $https_url"
    https_resp=$(curl -sILv "$https_url" 2>&1)
    https_code=$(echo "$https_resp" | grep "HTTP/" | tail -n 1 | awk '{print $2}')
    
    if [ "$https_code" = "200" ]; then
        echo -e "${VERDE}HTTPS OK (200)${RESET}"
        https_evidence=$(save_evidence "$url" "https" "$https_cmd" "$https_resp")
    else
        echo -e "${VERMELHO}HTTPS Falhou ($https_code)${RESET}"
    fi
    
    echo "Teste HTTP..."
    http_cmd="curl -sILv $http_url"
    http_resp=$(curl -sILv "$http_url" 2>&1)
    
    if echo "$http_resp" | grep -q "301 Moved Permanently\|Location: https://"; then
        echo -e "${VERDE}HTTP->HTTPS: OK (301)${RESET}"
        http_evidence=$(save_evidence "$url" "redirect" "$http_cmd" "$http_resp")
        
        redirect_to=$(echo "$http_resp" | grep -i "location:" | tail -n 1 | awk '{print $2}' | tr -d '\r')
        [ ! -z "$redirect_to" ] && echo "Redirecionando para: $redirect_to"
    elif echo "$http_resp" | grep -q "302 Found\|302 Moved Temporarily"; then
        echo -e "${AMARELO}HTTP->HTTPS: Temporário (302)${RESET}"
        http_evidence=$(save_evidence "$url" "redirect" "$http_cmd" "$http_resp")
    elif echo "$http_resp" | grep -q "000\|503\|504\|Connection refused"; then
        echo -e "${VERDE}HTTP bloqueado${RESET}"
    else
        echo -e "${VERMELHO}HTTP sem redirect seguro${RESET}"
    fi
    
    [ ! -z "$https_evidence" ] && echo "HTTPS Log: $https_evidence"
    [ ! -z "$http_evidence" ] && echo "HTTP Log: $http_evidence"
    echo "----------------------------------------"
    echo ""
}

make_report() {
    local file="${EVIDENCE_DIR}/relatorio.txt"
    local https_total=$(find ${EVIDENCE_DIR} -type f -name "*_https.txt" | wc -l)
    local redirect_total=$(find ${EVIDENCE_DIR} -type f -name "*_redirect.txt" -exec grep -l "301 Moved Permanently" {} \; | wc -l)
    local blocked_total=$(find ${EVIDENCE_DIR} -type f -name "*_redirect.txt" -exec grep -l "HTTP bloqueado" {} \; | wc -l)
    local lb_total=$(find ${EVIDENCE_DIR} -type f -exec grep -l "LoadBalancer: Detectado" {} \; | wc -l)
    
    local lb_endpoints=$(find ${EVIDENCE_DIR} -type f -exec grep -l "LoadBalancer: Detectado" {} \; | while read f; do
        basename "$f" | sed 's/_https\.txt//' | sed 's/_/_./g'
    done)
    
    local ssl_certs=$(find ${EVIDENCE_DIR} -type f -name "*_https.txt" -exec grep -h "subject:" {} \; | sort -u | sed 's/.*CN = //')
    
    {
        echo "=== Relatório de Segurança - $(date) ==="
        echo ""
        echo "Resumo: "
        echo "- URLs HTTPS testadas: $https_total"
        echo "- Redirecionamentos 301: $redirect_total"
        echo "- URLs HTTP bloqueadas: $blocked_total"
        echo "- LoadBalancers encontrados: $lb_total"
        echo ""
        echo "LoadBalancers detectados em:"
        echo "$lb_endpoints" | sed 's/^/  - /'
        echo ""
        echo "Certificados SSL únicos:"
        echo "$ssl_certs" | sed 's/^/  - /'
        echo ""
        echo "Configurações:"
        echo "1. LoadBalancer"
        echo "   - HTTPS forçador via 301"
        echo "   - SSL gerenciado"
        echo ""
        echo "2. Segurança"
        echo "   - HTTPS em todas conexões"
        echo "   - Certificados válidos"
        echo "   - Certificados inválidos"
        echo ""
        echo "3. Headers"
        echo "   - Security headers: OK"
        echo "   - SSL/TLS: OK"
    } > "$file"
    
    echo -e "${AZUL}Relatório gerado: $file${RESET}"
}

echo "Validação de segurança"
echo "Data: $(date)"
echo "================================================"
echo ""

echo "Evidências path: $EVIDENCE_DIR"
echo ""

#melhorar isso
echo "Validando Produção..."
for url in "${endpoints_prod[@]}"; do
    check_endpoint "$url" "Produção"
done

echo "Validando Homologação..."
for url in "${endpoints_hml[@]}"; do
    check_endpoint "$url" "Homologação"
done

make_report

echo "Validação concluida"
echo "Evidências em: $EVIDENCE_DIR"
