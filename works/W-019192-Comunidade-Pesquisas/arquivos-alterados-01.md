# Arquivos alterados 01 — Comunidade Pesquisas

## Identificação

| Item | Valor |
|---|---|
| Work | `W-019192` |
| Plano correspondente | `plano-implementacao-01.md` |
| Data | 2026-06-19 |
| Situação | Implementação e deploy granular concluídos; site em preview/UnderConstruction |

## Criados

### Dados

- `data/empreendimentos.csv`

### Apex

- `force-app/main/default/classes/PesquisasPortalController.cls`
- `force-app/main/default/classes/PesquisasPortalController.cls-meta.xml`
- `force-app/main/default/classes/PesquisasPortalControllerTest.cls`
- `force-app/main/default/classes/PesquisasPortalControllerTest.cls-meta.xml`
- `force-app/main/default/classes/PesquisasPortalDTOs.cls`
- `force-app/main/default/classes/PesquisasPortalDTOs.cls-meta.xml`
- `force-app/main/default/classes/PesquisasPortalSecurity.cls`
- `force-app/main/default/classes/PesquisasPortalSecurity.cls-meta.xml`
- `force-app/main/default/classes/PesquisasPortalSecurityTest.cls`
- `force-app/main/default/classes/PesquisasPortalSecurityTest.cls-meta.xml`
- `force-app/main/default/classes/PesquisasPortalService.cls`
- `force-app/main/default/classes/PesquisasPortalService.cls-meta.xml`
- `force-app/main/default/classes/PesquisasPortalServiceTest.cls`
- `force-app/main/default/classes/PesquisasPortalServiceTest.cls-meta.xml`

### Empreendimento

- `force-app/main/default/objects/Empreendimento__c/Empreendimento__c.object-meta.xml`
- `force-app/main/default/objects/Empreendimento__c/fields/Ativo__c.field-meta.xml`
- `force-app/main/default/objects/Empreendimento__c/fields/Bairro__c.field-meta.xml`
- `force-app/main/default/objects/Empreendimento__c/fields/Codigo__c.field-meta.xml`
- `force-app/main/default/objects/Empreendimento__c/fields/Regiao__c.field-meta.xml`
- `force-app/main/default/layouts/Empreendimento__c-Layout de Empreendimento.layout-meta.xml`

### Lead

- `force-app/main/default/objects/Lead/fields/Bairro_Desejado__c.field-meta.xml`
- `force-app/main/default/objects/Lead/fields/CPF__c.field-meta.xml`
- `force-app/main/default/objects/Lead/fields/CPF_Normalizado__c.field-meta.xml`
- `force-app/main/default/objects/Lead/fields/Data_Pretendida__c.field-meta.xml`
- `force-app/main/default/objects/Lead/fields/Empreendimento__c.field-meta.xml`
- `force-app/main/default/objects/Lead/fields/Observacoes_Agendamento__c.field-meta.xml`
- `force-app/main/default/objects/Lead/fields/Origem_Formulario__c.field-meta.xml`
- `force-app/main/default/objects/Lead/fields/Periodo_Preferido__c.field-meta.xml`
- `force-app/main/default/objects/Lead/fields/Regiao_Desejada__c.field-meta.xml`
- `force-app/main/default/objects/Lead/fields/Telefone_Normalizado__c.field-meta.xml`

### Activity/Task

- `force-app/main/default/objects/Activity/fields/Empreendimento__c.field-meta.xml`
- `force-app/main/default/objects/Activity/fields/Estrelas_Avaliacao__c.field-meta.xml`
- `force-app/main/default/objects/Activity/fields/Loja__c.field-meta.xml`
- `force-app/main/default/objects/Activity/fields/Nome_Vendedor__c.field-meta.xml`
- `force-app/main/default/objects/Activity/fields/Nota_Avaliacao__c.field-meta.xml`
- `force-app/main/default/objects/Activity/fields/Tipo_Registro_Pesquisas__c.field-meta.xml`

### LWC

- `force-app/main/default/lwc/pesquisasPortal/pesquisasPortal.html`
- `force-app/main/default/lwc/pesquisasPortal/pesquisasPortal.js`
- `force-app/main/default/lwc/pesquisasPortal/pesquisasPortal.css`
- `force-app/main/default/lwc/pesquisasPortal/pesquisasPortal.js-meta.xml`
- `force-app/main/default/lwc/pesquisasPortal/__tests__/pesquisasPortal.test.js`
- `force-app/main/default/lwc/pesquisasHome/pesquisasHome.html`
- `force-app/main/default/lwc/pesquisasHome/pesquisasHome.js`
- `force-app/main/default/lwc/pesquisasHome/pesquisasHome.css`
- `force-app/main/default/lwc/pesquisasHome/pesquisasHome.js-meta.xml`
- `force-app/main/default/lwc/pesquisasHome/__tests__/pesquisasHome.test.js`
- `force-app/main/default/lwc/pesquisasIdentificacao/pesquisasIdentificacao.html`
- `force-app/main/default/lwc/pesquisasIdentificacao/pesquisasIdentificacao.js`
- `force-app/main/default/lwc/pesquisasIdentificacao/pesquisasIdentificacao.css`
- `force-app/main/default/lwc/pesquisasIdentificacao/pesquisasIdentificacao.js-meta.xml`
- `force-app/main/default/lwc/pesquisasIdentificacao/__tests__/pesquisasIdentificacao.test.js`
- `force-app/main/default/lwc/pesquisasAgendamento/pesquisasAgendamento.html`
- `force-app/main/default/lwc/pesquisasAgendamento/pesquisasAgendamento.js`
- `force-app/main/default/lwc/pesquisasAgendamento/pesquisasAgendamento.css`
- `force-app/main/default/lwc/pesquisasAgendamento/pesquisasAgendamento.js-meta.xml`
- `force-app/main/default/lwc/pesquisasRecepcao/pesquisasRecepcao.html`
- `force-app/main/default/lwc/pesquisasRecepcao/pesquisasRecepcao.js`
- `force-app/main/default/lwc/pesquisasRecepcao/pesquisasRecepcao.css`
- `force-app/main/default/lwc/pesquisasRecepcao/pesquisasRecepcao.js-meta.xml`
- `force-app/main/default/lwc/pesquisasAvaliacao/pesquisasAvaliacao.html`
- `force-app/main/default/lwc/pesquisasAvaliacao/pesquisasAvaliacao.js`
- `force-app/main/default/lwc/pesquisasAvaliacao/pesquisasAvaliacao.css`
- `force-app/main/default/lwc/pesquisasAvaliacao/pesquisasAvaliacao.js-meta.xml`
- `force-app/main/default/lwc/pesquisasAvaliacao/__tests__/pesquisasAvaliacao.test.js`

### Experience Cloud

- `force-app/main/default/digitalExperiences/site/Pesquisas1/**` — 55 arquivos gerados pelo Salesforce; Home ajustada para `c:pesquisasPortal` e propriedade incompatível `geoBotsAllowed` removida do source.
- `force-app/main/default/networks/Pesquisas.network-meta.xml`
- `force-app/main/default/sites/Pesquisas.site-meta.xml`
- `force-app/main/default/profiles/Pesquisas Profile.profile-meta.xml`

### Rastreabilidade

- `works/W-019192-Comunidade-Pesquisas/plano-implementacao-01.md`
- `works/W-019192-Comunidade-Pesquisas/arquivos-alterados-01.md`

## Alterados

- `Manifest/package.xml`

## Removidos

Nenhum.

## Deploys executados

| Conteúdo | Resultado | Id |
|---|---|---|
| Modelo de dados | `Succeeded` | `0Afak00000cFACTCA4` |
| Lookup Activity → Empreendimento | `Succeeded` | `0Afak00000cFAqnCAG` |
| Apex + testes | `Succeeded` | `0Afak00000cF9wMCAS` |
| LWC final | `Succeeded` | `0Afak00000cFCCfCAO` |
| Experience Cloud + Guest Profile | `Succeeded` | `0Afak00000cFFiPCAW` |

Nenhum deploy utilizou o `package.xml` completo. Nenhuma carga, publicação ou ativação foi executada.
