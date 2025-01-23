Validador de Segurança de Endpoints:

Este script bash foi criado para automatizar a verificação de segurança de endpoints HTTP e HTTPS por grupos. Ele verifica a presença de características de segurança, incluindo HTTPS forçado, certificados SSL/TLS válidos, load balancers e redirecionamentos.

Recursos Suportados:

HTTPS: Verifica se o endpoint é acessível apenas via HTTPS.

Certificados SSL/TLS: Verifica se os certificados SSL/TLS estão válidos e atualizados.

Load Balancers: Deteta a presença de load balancers e identifica se eles estão configurados para forçar HTTPS.

Redirecionamentos: Verifica se os redirecionamentos são seguros (301) e identifica se eles estão sendo gerados por load balancers.
