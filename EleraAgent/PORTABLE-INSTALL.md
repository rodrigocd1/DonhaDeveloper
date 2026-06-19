# Elera Agent Work Validation - Portable Install

## Objetivo

Instalar a validacao de Work da org Elera em outro projeto Salesforce com os scripts, instrucoes e verificadores necessarios para consultar `agf__ADM_Work__c` via Salesforce CLI e JWT Bearer Flow.

## Instalacao rapida

Extraia o ZIP na raiz do projeto destino preservando os caminhos relativos.

Se o projeto destino estiver na mesma maquina e o alias global `elera-work-check` ja existir no Salesforce CLI, a consulta ja deve funcionar diretamente:

```powershell
scripts/check-work.ps1 "W-018973"
```

Depois, no Windows, se a chave privada local ja existir em `C:\Users\<usuario>\.salesforce-jwt\elera-work-check.key`, configure o ambiente assim:

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

- Salesforce CLI (`sf`) instalado no ambiente destino.
- PowerShell no Windows.
- Bash e Node.js para uso dos scripts `.sh`.
- External Client App ja configurada na org Elera com o certificado publico correspondente.
- Usuario `integration.cli@elera.io` pre-autorizado e com permissao minima de leitura da Work.

## Arquivos locais obrigatorios

O ZIP entrega os scripts e documentos, mas a chave privada JWT precisa existir localmente fora do projeto.

Caminho Windows recomendado:

```text
C:\Users\<usuario>\.salesforce-jwt\elera-work-check.key
```

Caminho Linux/macOS recomendado:

```text
~/.salesforce-jwt/elera-work-check.key
```

## Conferencia do pacote

O pacote contem:

- scripts de autenticacao JWT;
- scripts de consulta da Work;
- verificadores Windows e Bash;
- exemplo de variaveis de ambiente;
- documentacao de setup;
- instrucoes de agente para exigir a validacao.

O pacote nao contem chave privada, tokens, refresh tokens, senha, client secret, `.sf/`, `.sfdx/` ou `.env` real.

Premissa operacional: para funcionar em outra maquina, a mesma chave privada correspondente ao certificado publico cadastrado na External Client App precisa estar disponivel fora do projeto, ou a app precisa ser atualizada com um novo certificado publico.
