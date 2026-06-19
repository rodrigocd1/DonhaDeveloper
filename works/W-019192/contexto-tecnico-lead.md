# Contexto técnico consolidado — Lead

## Identificação da auditoria

| Item | Valor |
|---|---|
| Work | `W-019192` (`FOUND`) |
| Org solicitada | `MyDeveloper` |
| Alias resolvido | `Donha_Developer` |
| Tipo de org | Developer Edition |
| API do projeto/retrieve | 65.0 |
| Data da coleta | 2026-06-18 |
| Resultado | Retrieve granular concluído com sucesso; nenhum deploy executado |

Este documento é um snapshot técnico da org no momento da coleta. Não define regra de negócio nova.

## Resumo executivo

- O objeto `Lead` está habilitado para criação, atualização, exclusão, merge e triggers.
- O describe retornou 60 campos. Somente `LastName` e `Company` são obrigatórios na criação por schema; `Status`, `OwnerId` e `CurrencyIsoCode` possuem valor padrão.
- Existem sete campos customizados no Lead. Nenhum campo do objeto está marcado como External ID ou Unique.
- Não existem Validation Rules, Workflow Rules, Approval Processes, Paths ou Apex Triggers de Lead identificados.
- Existe um Process Builder `PB_3_Lead`: versão 5 ativa e versão 6 em rascunho. Na criação do Lead, a versão ativa envia notificação customizada ao proprietário.
- A regra de atribuição `Standard` está ativa e direciona Leads para o mesmo usuário específico, tanto para países dos EUA quanto para os demais países.
- As duas Duplicate Rules Lead/Contact estão inativas e configuradas para permitir insert/update.
- O compartilhamento interno e externo do Lead é `ReadWriteTransfer`; não há Sharing Rules de Lead.
- O histórico de Lead está desabilitado.
- Não foi identificada integração customizada Apex para Lead. Há dois Web Links do pacote Conga e configuração Web-to-Lead sem filtro antispam.

## Cobertura do retrieve

Foram mantidos 101 arquivos de metadata relacionados ao escopo:

| Diretório/tipo | Quantidade | Conteúdo |
|---|---:|---|
| `objects` | 50 | Lead, 33 metadados de campo, processo, listas, links e dependências Account/Visita |
| `profiles` | 32 | CRUD, FLS e atribuições de layout retornadas no retrieve parcial |
| `layouts` | 5 | Quatro layouts de Lead e o layout dependente de Visita |
| `duplicateRules` | 2 | Regras cruzadas Lead/Contact |
| `matchingRules` | 2 | Containers de Lead e Contact; sem regras customizadas recuperáveis |
| `standardValueSets` | 2 | `LeadStatus` e `LeadSource` |
| `settings` | 2 | `LeadConfig` e `WebToX` |
| Demais tipos | 8 | Assignment, Auto Response, Flow, Quick Action, Sharing e Custom Notification |

O inventário combinou Metadata API, describe do objeto, Tooling API, `MetadataComponentDependency` e busca estática no código local.

## Modelo de dados

### Campos obrigatórios e defaults de criação

| Campo | Tipo | Regra técnica |
|---|---|---|
| `LastName` | Text(80) | Obrigatório pelo schema |
| `Company` | Text(255) | Obrigatório pelo schema |
| `Status` | Picklist | Default `Open - Not Contacted` |
| `OwnerId` | Lookup(User/Queue) | Default fornecido pela plataforma/contexto de execução |
| `CurrencyIsoCode` | Picklist | Default `USD`; única moeda disponível no describe |

`Name` e `Address` são campos compostos e não são graváveis diretamente pela API; devem ser usados seus componentes.

### Campos funcionais padrão graváveis

| Grupo | Campos principais |
|---|---|
| Identificação | `FirstName`, `LastName`, `Salutation`, `Company`, `Title` |
| Contato | `Phone`, `MobilePhone`, `Fax`, `Email`, `Website`, `DoNotCall`, `HasOptedOutOfEmail`, `HasOptedOutOfFax` |
| Endereço | `Street`, `City`, `State`, `PostalCode`, `Country`, `Latitude`, `Longitude`, `GeocodeAccuracy` |
| Qualificação | `LeadSource`, `Status`, `Industry`, `Rating`, `AnnualRevenue`, `NumberOfEmployees`, `Description` |
| Relacionamentos | `OwnerId`, `CampaignId`, `PartnerAccountId`, `IndividualId` |

Campos de conversão como `ConvertedDate`, `ConvertedAccountId`, `ConvertedContactId` e `ConvertedOpportunityId` são mantidos pela plataforma. `IsConverted` não é atualizável após a criação.

### Campos customizados do Lead

| Campo | Tipo | Obrigatório | External ID/Unique | Observação |
|---|---|---:|---:|---|
| `SICCode__c` | Text(15) | Não | Não/Não | Código SIC |
| `ProductInterest__c` | Picklist | Não | Não/Não | `GC1000 series`, `GC5000 series`, `GC3000 series` |
| `Primary__c` | Picklist | Não | Não/Não | `No`, `Yes` |
| `CurrentGenerators__c` | Text(100) | Não | Não/Não | Geradores atuais |
| `NumberofLocations__c` | Number(3,0) | Não | Não/Não | Quantidade de localidades |
| `Data_Quality_Score__c` | Formula Number(18,0) | Não | Não/Não | Somatório de completude de dados |
| `Data_Quality_Description__c` | Formula Text(1300) | Não | Não/Não | Informa campos ausentes |

O score de qualidade totaliza 100 pontos: 15 pontos para cada um de `FirstName`, `LastName`, `Company` e `Phone`; 10 pontos para cada um de `Salutation`, `Rating`, `City` e `Email`. Esses campos são indicadores e não bloqueiam DML.

### Picklists relevantes

`LeadStatus` possui quatro valores:

- `Open - Not Contacted` — default, não convertido.
- `Working - Contacted` — não convertido.
- `Closed - Converted` — convertido.
- `Closed - Not Converted` — fechado, não convertido.

`LeadSource` possui: `Anúncio`, `Indicação de funcionário`, `Indicação externa`, `Parceiro`, `Relações públicas`, `Seminário - Interno`, `Seminário - Parceiro`, `Feira ou convenção`, `Web`, `Boca a boca` e `Outros`.

Há somente o Record Type `Master`. O Business Process `Lead Process` está ativo, usa os quatro status e define `Open - Not Contacted` como default.

## Criação e atualização

### Quick Action `NewLead`

- Tipo: criação de `Lead`.
- Obrigatórios na ação: `Name` e `Company`.
- Editáveis na ação: `Email`, `Phone` e `Title`.
- Cria item no feed.

### Requisitos de layout

Todos os layouts marcam `Name`, `Company`, `Status` e `CurrencyIsoCode` como obrigatórios. O layout de Marketing também marca `LeadSource` como obrigatório. Requisitos de layout são de interface e não substituem schema, Validation Rule ou validação explícita de integração.

Não existem Validation Rules no Lead. Portanto, além das restrições nativas de tipo/tamanho/picklist, não foi recuperado bloqueio declarativo adicional para insert/update.

## Automação

### Process Builder `PB_3_Lead`

| Item | Configuração ativa |
|---|---|
| Versão ativa | 5 |
| Versão mais recente | 6, `Draft` |
| API | 49.0 |
| Processo | `Workflow`/Process Builder |
| Evento | Somente criação (`onCreateOnly`, fórmula `ISNEW()`) |
| Ação | `customNotificationAction` |
| Destinatário | `OwnerId` do Lead |
| Tipo de notificação | `Notificao_lead` — label `Notificação lead`, desktop e mobile |
| Título | Nome do novo Lead |
| Corpo | `Testeo` |
| Target | ID do Lead criado |

O arquivo `PB_3_Lead.flow-meta.xml` recuperado pela Metadata API representa a versão 6 em rascunho. A versão 5 ativa foi consultada diretamente via Tooling API e possui o comportamento descrito acima. As versões 1 a 4 estão obsoletas.

Nenhum outro Flow ativo ou em rascunho da org referencia Lead.

### Assignment Rules

A regra `Standard` está ativa e possui duas entradas:

1. `Lead.Country` igual a `US`, `USA`, `United States` ou `United States of America`.
2. `Lead.Country` diferente desses valores.

As duas entradas atribuem ao mesmo usuário específico da org. Não há fila ou distribuição diferenciada entre as condições. Chamadas por API/Apex precisam solicitar a execução da Assignment Rule; DML comum não a aplica implicitamente.

### Auto Response, Workflow e Apex

- `Lead.autoResponseRules-meta.xml` está vazio: nenhuma Auto-Response Rule recuperada.
- Nenhuma Workflow Rule de Lead foi encontrada via Metadata/Tooling API.
- Nenhum Apex Trigger está associado ao objeto Lead.
- O grafo de dependências não retornou Apex Class dependente de Lead.
- A busca estática em Apex, Aura, Visualforce e JavaScript encontrou apenas o mapeamento visual `Lead: 'standard:lead'` em `communicatorChatPicker.js`; não é lógica de negócio de Lead.

## Deduplicação

Existem duas regras cruzadas:

| Regra | Objeto de entrada | Compara com | Ativa | Insert/Update |
|---|---|---|---:|---|
| Leads com Contatos duplicados | Lead | Contact | Não | Allow/Allow |
| Contatos com Leads duplicados | Contact | Lead | Não | Allow/Allow |

As regras usam as Matching Rules padrão `Standard_Contact_Match_Rule_v1_1` e `Standard_Lead_Match_Rule_v1_0`. Os campos mapeados são nome, sobrenome, telefone, email, cidade, rua, CEP, cargo e empresa/conta.

Na configuração recuperada, insert gera `Alert` e `Report`; update gera `Report`; o compartilhamento é respeitado. Contudo, ambas as regras estão inativas e a ação configurada é permitir. Os arquivos `MatchingRules` vieram vazios porque não há Matching Rule customizada recuperável; as regras referenciadas são padrão Salesforce.

Não existe campo External ID ou Unique no Lead para idempotência nativa por chave externa.

## Conversão de Lead

`LeadConfig` contém:

| Configuração | Valor |
|---|---:|
| Preservar status do Lead | Sim |
| Exigir validações durante conversão | Sim |
| Ocultar Opportunity na janela de conversão | Não |
| Selecionar por padrão “sem Opportunity” | Não |
| Conversão em dispositivo móvel | Não |
| Merge e delete em toda a org | Sim |
| Histórico de Lead | Não |
| Notificar por email quando owner muda via Apex no LEX | Não |

Nenhum arquivo `LeadConvertSettings` foi retornado, portanto não foi identificado mapeamento customizado de campos de conversão por esse metadata. O campo `Account.LeadTipoRegistro__c` (Text 40, opcional) existe nominalmente para informação de tipo de registro do Lead, mas nenhum metadata recuperado comprova seu preenchimento ou mapeamento automático.

## Relacionamentos customizados

| Campo | Relacionamento | Exclusão do Lead | Obrigatório |
|---|---|---|---:|
| `Visita__c.Lead__c` | Lookup para Lead; relacionamento `Visitas` | `SetNull` | Não |
| `Visita_Expers__c.Lead__c` | Lookup para Lead; relacionamento `Visitas_Expers` | `SetNull` | Não |

Os quatro layouts de Lead exibem a related list `Visita__c.Lead__c`. O layout `Visita__c-Layout de Visita` permite editar `Lead__c`. O lookup de `Visita_Expers__c` não apareceu como related list nos layouts recuperados.

## Segurança e compartilhamento

- OWD interno: `ReadWriteTransfer`.
- OWD externo: `ReadWriteTransfer`.
- Nenhuma Sharing Rule de Lead foi recuperada.
- Admin: CRUD, View All e Modify All.
- CRUD explícito: `ContractManager`, `Custom: Marketing Profile`, `Custom: Sales Profile`, `Custom: Support Profile`, `MarketingProfile`, `SolutionManager` e `Standard`.
- Create/Read/Edit sem Delete: `Gold Partner User`, `Silver Partner User`, `Partner Community Login User` e `Partner Community User`.
- Somente leitura: `Read Only`.
- Nenhum Permission Set recuperável retornou permissão explícita de objeto ou campo para Lead.

Perfis sem `objectPermissions` explícita de Lead foram omitidos da relação acima. A presença isolada de FLS ou atribuição de layout no arquivo parcial não concede CRUD. Os 32 arquivos de Profile são resultados parciais do package de retrieve e não representam todo o conteúdo dos perfis.

As fórmulas de qualidade aparecem em FLS de alguns perfis, mas o describe marca ambas como não criáveis e não atualizáveis; prevalece o comportamento do schema.

## Layouts e navegação

| Layout | Uso identificado | Particularidades |
|---|---|---|
| `Lead-Lead Layout` | Admin e perfis gerais | Inclui todos os cinco campos customizados editáveis não fórmula |
| `Lead-Lead (Marketing) Layout` | `Custom: Marketing Profile` | `LeadSource` obrigatório no layout; inclui `Primary__c` e `SICCode__c` |
| `Lead-Lead (Sales) Layout` | `Custom: Sales Profile` | Inclui `ProductInterest__c`, `NumberofLocations__c`, `CurrentGenerators__c` |
| `Lead-Lead (Support) Layout` | `Custom: Support Profile` | Conjunto reduzido de campos adicionais |

Todos possuem seções de informações do Lead, endereço, adicionais, sistema e descrição, além de atividades, histórico, status de email e Visitas.

List Views recuperadas: `AllOpenLeads`, `Arbole_1_Lead`, `Arbole_2_Lead`, `MyUnreadLeads`, `TodaysLeads`, `ViewCustom1` e `ViewCustom2`. As listas `Arbole_1_Lead` e `Arbole_2_Lead` usam escopo de fila.

## Integrações e canais de entrada

### Web-to-Lead

O metadata `WebToX` retornou `webToLeadSpamFilter=false`. Isso comprova que o filtro antispam está desabilitado; o metadata não contém formulário HTML, endpoint consumidor ou regra de transformação.

### Conga

O objeto Lead possui dois Web Links do pacote `APXTConga4`:

- `Conga Composer (OAuth)`: abre a Visualforce gerenciada `APXTConga4__Conga_Composer` com o `Lead.Id`.
- `Conga Composer`: usa endpoint externo do Conga com session ID, Partner Server URL versão 29.0 e `Lead.Id`.

As próprias descrições dos metadados orientam não adicionar esses botões diretamente ao layout. Nenhum dos quatro layouts recuperados contém colocação explícita desses links.

### Integração customizada

Não foi recuperada classe Apex, trigger, Flow adicional, Named Credential ou Remote Site com dependência comprovada de Lead. Isso não exclui consumidores externos que usem APIs padrão Salesforce, Web-to-Lead ou referências dinâmicas não representadas em metadata.

## Ausências comprovadas e limitações

- Sem Validation Rule, Workflow Rule, Approval Process ou Path de Lead.
- Sem Apex Trigger de Lead.
- Sem Flow de Lead além de `PB_3_Lead` entre as 12 versões ativas/rascunho inspecionadas.
- Sem Auto-Response Rule e Sharing Rule efetivas.
- Sem Record Type além de Master.
- Sem Matching Rule customizada recuperável.
- Sem External ID ou Unique no Lead.
- `LeadConvertSettings` não retornou arquivo.
- Matching Rules padrão, formulários Web-to-Lead, consumidores externos e configurações internas não expostas pela Metadata API não podem ser detalhados por este retrieve.

## Restrições para futura orquestração técnica

1. Usar a versão 5 ativa do `PB_3_Lead` como comportamento vigente; a versão 6 local está em rascunho.
2. Não assumir bloqueio de duplicidade: as Duplicate Rules estão inativas, permitem DML e não há chave externa única.
3. Tratar `LastName` e `Company` como obrigatórios em qualquer canal de criação; requisitos adicionais de layout não valem automaticamente para API.
4. Definir explicitamente se uma integração deve executar Assignment Rules e Duplicate Rules, pois isso depende das opções do canal de DML.
5. Considerar CRUD/FLS do usuário de execução e o compartilhamento público `ReadWriteTransfer`.
6. Em conversão, considerar que a org exige validações e preserva o status do Lead.
7. Não inferir preenchimento de `Account.LeadTipoRegistro__c` sem evidência adicional de mapeamento ou automação.

## Arquivos-fonte principais

- `force-app/main/default/objects/Lead/`
- `force-app/main/default/layouts/Lead-*`
- `force-app/main/default/flows/PB_3_Lead.flow-meta.xml`
- `force-app/main/default/assignmentRules/Lead.assignmentRules-meta.xml`
- `force-app/main/default/duplicateRules/`
- `force-app/main/default/settings/LeadConfig.settings-meta.xml`
- `force-app/main/default/settings/WebToX.settings-meta.xml`
- `force-app/main/default/profiles/`
- `Manifest/package.xml`
