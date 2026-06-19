# Elera Work Check Setup

## Objetivo

Esta configuracao prepara a validacao automatica de Work na org Salesforce Elera usando Salesforce CLI, JWT Bearer Flow, usuario de integracao e scripts locais com saida curta.

O objetivo e permitir que agentes validem uma Work com baixo consumo de tokens executando apenas:

Windows:

```powershell
scripts/check-work.ps1 "W-018973"
```

Linux, macOS ou Git Bash:

```bash
scripts/check-work.sh "W-018973"
```

## Seguranca

Nao use senha para automacao. Senhas e refresh tokens aumentam risco operacional e podem ficar gravados em historico, logs ou arquivos locais.

Nao crie endpoint REST publico sem autenticacao. A validacao consulta Salesforce via CLI autenticada, com permissoes minimas e rastreabilidade do usuario de integracao.

Nunca grave no repositorio:

- senha;
- token;
- refresh token;
- client secret;
- chave privada;
- arquivo `.env` real;
- arquivos `.key`, `.pem`, `.p12` ou `.jks`.

## Variaveis de ambiente

Configure estas variaveis fora do repositorio:

```text
SF_ELERA_USERNAME=integration.cli@elera.io
SF_ELERA_CLIENT_ID=<consumer-key-da-external-client-app>
SF_ELERA_JWT_KEY_FILE=<caminho-absoluto-da-chave-privada>
SF_ELERA_INSTANCE_URL=https://login.salesforce.com
```

O arquivo `.env.example` contem apenas placeholders. Nao copie valores reais para arquivos versionados.

## Certificado e chave privada

Gere o certificado e a chave privada fora do repositorio.

Exemplo Windows:

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.salesforce-jwt"
openssl req -newkey rsa:2048 -nodes -keyout "$env:USERPROFILE\.salesforce-jwt\elera-work-check.key" -x509 -days 3650 -out "$env:USERPROFILE\.salesforce-jwt\elera-work-check.crt"
```

Exemplo Linux ou macOS:

```bash
mkdir -p ~/.salesforce-jwt
openssl req -newkey rsa:2048 -nodes -keyout ~/.salesforce-jwt/elera-work-check.key -x509 -days 3650 -out ~/.salesforce-jwt/elera-work-check.crt
```

A chave privada deve ficar somente fora do projeto. O certificado publico pode ser carregado na External Client App.

## External Client App

A External Client App deve permitir JWT Bearer Flow para o usuario `integration.cli@elera.io`.

Configuracao esperada:

- OAuth habilitado;
- certificado publico carregado;
- escopos `Api` e `RefreshToken`;
- policy de usuarios `AdminApprovedPreAuthorized`;
- Permission Set `Elera_Work_Check_Read_Only` atribuida ao usuario de integracao.

Nesta base, a configuracao fica em metadata de External Client App, nao em Connected App tradicional. Se a org nao aceitar a criacao por metadata, finalize a configuracao manualmente na tela da app e mantenha os mesmos scopes e policies.

## Permission Set minima

A Permission Set `Elera_Work_Check_Read_Only` concede:

- `ApiEnabled`;
- leitura no objeto `agf__ADM_Work__c`;
- leitura no campo `agf__ADM_Work__c.Name`;
- sem Create, Edit, Delete, View All ou Modify All.

Se a org ou o pacote gerenciado nao aceitar a permissao por metadata, atribua manualmente permissao equivalente ao usuario `integration.cli@elera.io`.

## Autenticacao JWT

Se o alias global `elera-work-check` ja estiver autenticado no Salesforce CLI da maquina, a validacao pode funcionar imediatamente em qualquer projeto local que tenha os scripts.

No Windows, se a chave privada estiver no caminho recomendado, voce pode configurar as variaveis locais com:

```powershell
scripts/setup-elera-work-check-env.ps1 "<consumer-key-da-external-client-app>"
```

Depois de configurar as variaveis de ambiente, execute:

Windows:

```powershell
scripts/auth-elera-work-check.ps1
```

Linux, macOS ou Git Bash:

```bash
scripts/auth-elera-work-check.sh
```

Saidas:

- `AUTH_OK`: alias `elera-work-check` autenticado;
- `AUTH_ERROR`: variaveis ausentes, chave inexistente, falha de CLI ou falha de autenticacao.

Para conferir manualmente o alias:

```bash
sf org display --target-org elera-work-check --json
```

## Verificacao local

Para conferir os componentes locais sem exibir segredos, execute:

```powershell
scripts/verify-elera-work-validation.ps1 "W-018973"
```

Linux, macOS ou Git Bash:

```bash
scripts/verify-elera-work-validation.sh "W-018973"
```

O verificador checa Salesforce CLI, variaveis de ambiente, existencia da chave local fora do repositorio, alias `elera-work-check`, script de validacao e resultado da Work.

## Validacao da Work

Execute:

Windows:

```powershell
scripts/check-work.ps1 "W-018973"
```

Linux, macOS ou Git Bash:

```bash
scripts/check-work.sh "W-018973"
```

Saidas:

- `FOUND`: a Work existe;
- `NOT_FOUND`: a Work nao existe;
- `INVALID_WORK`: a entrada nao segue o padrao `W-xxxxxx`;
- `AUTH_ERROR`: o alias `elera-work-check` nao esta autenticado ou nao tem permissao para consultar.

O script consulta:

```sql
SELECT Id
FROM agf__ADM_Work__c
WHERE Name = '<WORK_NORMALIZADA>'
LIMIT 1
```

## Normalizacao da Work

Exemplos:

- `W-1` vira `W-000001`;
- `w-25` vira `W-000025`;
- `works/W-000001/` vira `W-000001`.

O agente nao deve gerar numero de Work. A pessoa deve informar a Work.

## VS Code

Se `.vscode/tasks.json` existir localmente, use:

- `Elera: Auth Work Check`;
- `Elera: Check Work`.

As tasks nao contem segredo, Consumer Key real nem caminho real de chave privada.

## Bootstrap

Esta alteracao prepara a propria infraestrutura de validacao. Por isso, ela pode ser feita sem uma Work especifica quando o objetivo for apenas criar o mecanismo inicial.

Depois deste bootstrap, toda implementacao deve validar a Work usando apenas `scripts/check-work.ps1` ou `scripts/check-work.sh`, salvo manutencao direta desses scripts.
