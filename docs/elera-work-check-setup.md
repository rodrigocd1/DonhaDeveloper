# Elera Work Check Setup

## Objetivo

Esta configuracao prepara a validacao automatica de Work na org Salesforce Elera usando Salesforce CLI, JWT Bearer Flow, usuario de integracao e scripts locais com saida curta.

Windows:

```powershell
scripts/check-work.ps1 "W-018973"
```

Linux, macOS ou Git Bash:

```bash
scripts/check-work.sh "W-018973"
```

## Seguranca

Nao use senha para automacao e nao crie endpoint REST publico sem autenticacao. Nunca grave no repositorio senha, token, refresh token, client secret, chave privada, `.env` real ou arquivos `.key`, `.pem`, `.p12` e `.jks`.

## Variaveis de ambiente

Configure fora do repositorio:

```text
SF_ELERA_USERNAME=integration.cli@elera.io
SF_ELERA_CLIENT_ID=<consumer-key-da-external-client-app>
SF_ELERA_JWT_KEY_FILE=<caminho-absoluto-da-chave-privada>
SF_ELERA_INSTANCE_URL=https://login.salesforce.com
```

O `.env.example` contem apenas placeholders.

## Certificado e chave privada

Windows:

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.salesforce-jwt"
openssl req -newkey rsa:2048 -nodes -keyout "$env:USERPROFILE\.salesforce-jwt\elera-work-check.key" -x509 -days 3650 -out "$env:USERPROFILE\.salesforce-jwt\elera-work-check.crt"
```

Linux ou macOS:

```bash
mkdir -p ~/.salesforce-jwt
openssl req -newkey rsa:2048 -nodes -keyout ~/.salesforce-jwt/elera-work-check.key -x509 -days 3650 -out ~/.salesforce-jwt/elera-work-check.crt
```

A chave privada deve ficar fora do projeto. Carregue somente o certificado publico na External Client App.

## External Client App

Configuracao esperada:

- OAuth habilitado;
- certificado publico carregado;
- scopes `Api` e `RefreshToken`;
- policy `AdminApprovedPreAuthorized`;
- Permission Set `Elera_Work_Check_Read_Only` atribuida ao usuario `integration.cli@elera.io`.

## Permission Set minima

A Permission Set concede `ApiEnabled` e leitura de `agf__ADM_Work__c.Name`, sem Create, Edit, Delete, View All ou Modify All.

## Autenticacao JWT

Windows:

```powershell
scripts/setup-elera-work-check-env.ps1 "<consumer-key-da-external-client-app>"
scripts/auth-elera-work-check.ps1
```

Linux, macOS ou Git Bash:

```bash
scripts/auth-elera-work-check.sh
```

Saidas: `AUTH_OK` ou `AUTH_ERROR`.

## Verificacao local

```powershell
scripts/verify-elera-work-validation.ps1 "W-018973"
```

```bash
scripts/verify-elera-work-validation.sh "W-018973"
```

## Validacao da Work

Os scripts retornam `FOUND`, `NOT_FOUND`, `INVALID_WORK` ou `AUTH_ERROR` e consultam:

```sql
SELECT Id
FROM agf__ADM_Work__c
WHERE Name = '<WORK_NORMALIZADA>'
LIMIT 1
```

Exemplos de normalizacao: `W-1` vira `W-000001`, `w-25` vira `W-000025` e `works/W-000001/` vira `W-000001`.

O agente nao deve gerar numero de Work. A pessoa deve informa-lo.

## VS Code

Use as tasks `Elera: Auth Work Check` e `Elera: Check Work`. Elas nao contem segredo, Consumer Key real nem caminho real de chave privada.

## Bootstrap

A infraestrutura de validacao pode ser instalada sem Work especifica. Depois do bootstrap, toda implementacao deve validar a Work pelos scripts, salvo manutencao direta deles.
