# Elera Agent Work Validation - Portable Install

## Objetivo

Instalar a validacao de Work da org Elera em outro projeto Salesforce com os scripts, instrucoes e verificadores necessarios para consultar `agf__ADM_Work__c` via Salesforce CLI e JWT Bearer Flow.

## Instalacao rapida

Extraia o ZIP na raiz do projeto destino preservando os caminhos relativos.

Se o alias global `elera-work-check` ja existir no Salesforce CLI, execute:

```powershell
scripts/check-work.ps1 "W-018973"
```

No Windows, configure e valide o ambiente assim:

```powershell
scripts/setup-elera-work-check-env.ps1 "<consumer-key-da-external-client-app>"
scripts/auth-elera-work-check.ps1
scripts/verify-elera-work-validation.ps1 "W-018973"
scripts/check-work.ps1 "W-018973"
```

No Linux, macOS ou Git Bash:

```bash
export SF_ELERA_USERNAME="integration.cli@elera.io"
export SF_ELERA_CLIENT_ID="<consumer-key-da-external-client-app>"
export SF_ELERA_JWT_KEY_FILE="$HOME/.salesforce-jwt/elera-work-check.key"
export SF_ELERA_INSTANCE_URL="https://login.salesforce.com"

scripts/auth-elera-work-check.sh
scripts/verify-elera-work-validation.sh "W-018973"
scripts/check-work.sh "W-018973"
```

## Resultado esperado

- `AUTH_OK`: autenticacao JWT feita.
- `FOUND`: Work encontrada.
- `NOT_FOUND`: Work nao encontrada.
- `INVALID_WORK`: formato invalido; use `W-xxxxxx`.
- `AUTH_ERROR`: autenticacao ou permissao minima ausente.

## Dependencias externas

- Salesforce CLI (`sf`).
- PowerShell no Windows.
- Bash e Node.js para scripts `.sh`.
- External Client App configurada na org Elera com o certificado publico correspondente.
- Usuario `integration.cli@elera.io` pre-autorizado e com permissao minima de leitura da Work.

## Arquivos locais obrigatorios

A chave privada JWT precisa existir fora do projeto.

Windows:

```text
C:\Users\<usuario>\.salesforce-jwt\elera-work-check.key
```

Linux/macOS:

```text
~/.salesforce-jwt/elera-work-check.key
```

O pacote nao contem chave privada, tokens, refresh tokens, senha, client secret, `.sf/`, `.sfdx/` ou `.env` real.
