# Plano de implementação 01 — Comunidade Pesquisas

## Identificação

| Item | Valor |
|---|---|
| Work | `W-019192` |
| Agente/modelo | Codex — GPT-5 |
| Configuração | Implementação Salesforce aprovada; deploy granular em `MyDeveloper`; sem publicação ou carga de dados |
| Data de início | 2026-06-19 |
| Org analisada | Alias `MyDeveloper` — Developer Edition, API 65.0 |
| Situação | Implementação e deploy granular concluídos em `MyDeveloper`; site em preview/UnderConstruction |

## Objetivo

Implementar uma comunidade pública Experience Cloud LWR chamada **Pesquisas**, responsiva para desktop, tablet, Android e iOS, com três jornadas independentes:

1. agendamento de visita;
2. recepção/check-in;
3. avaliação do atendimento.

A solução deverá criar e relacionar Leads e Tasks com segurança, sem expor dados pessoais ao usuário público e sem alterar comportamentos existentes fora do escopo.

## Motivo

Disponibilizar uma experiência pública única para captação, recepção e avaliação, com rastreabilidade no Salesforce, preservando as automações atuais de Lead e Task e permitindo evolução controlada do processo.

## Portões de autorização

| Portão | Situação | Efeito |
|---|---|---|
| Análise técnica | Aprovada pelo solicitante | Permitiu consolidar este plano |
| Plano de implementação | Aprovado pelo solicitante | Recomendações técnicas aceitas |
| Implementação e deploy granular em `MyDeveloper` | Autorizado e concluído | Modelo, Apex, LWC, Experience Cloud e Guest Profile implantados |
| Publicação/ativação da comunidade | Fora da aprovação deste plano | Exigirá autorização explícita separada após homologação |
| Carga dos cinco Empreendimentos | Fora da aprovação deste plano | O arquivo será preparado; a carga exigirá autorização explícita |

A criação do site por CLI foi concluída após liberação de storage e autorização do fallback `Build Your Own (LWR)`. A comunidade permanece não publicada e `UnderConstruction`.

## Resultado do diagnóstico técnico

### Projeto local

- Projeto Salesforce DX com diretório padrão `force-app` e API 65.0.
- Existem padrões reutilizáveis de controller fino, service, DTOs, sanitização e testes Apex.
- Não há metadados Experience Cloud versionados atualmente no projeto.
- Há infraestrutura Jest para LWC.
- A branch atual é `main`, protegida pelas regras do projeto. Não será feito commit, push, merge ou rebase.
- O worktree contém alterações anteriores e não relacionadas; elas serão preservadas.

### Experience Cloud

- Digital Experiences e domínio de sites já estão habilitados.
- Existem três comunidades, mas nenhuma chamada `Pesquisas` e nenhum prefixo `pesquisas`.
- A org oferece os templates `Microsite (LWR)` e `Build Your Own (LWR)`.
- O padrão LWR existente na org foi validado por retrieve temporário, sem alteração do projeto.
- O template inicialmente proposto foi `Microsite (LWR)`. Após falhas do job e autorização explícita, a implementação foi concluída com `Build Your Own (LWR)` e acesso público habilitado.
- O nome técnico exato de `Network`, `CustomSite`, `DigitalExperienceBundle` e Guest Profile será gerado pelo Salesforce e confirmado por retrieve; não serão inventados IDs ou nomes internos.

### Modelo de dados

- Não existe objeto de Empreendimento, Projeto, Imóvel ou Residencial que atenda ao requisito.
- Lead não possui campos de CPF, CPF normalizado, Empreendimento, região/bairro desejados, data/período ou origem do formulário.
- Lead exige `LastName` e `Company` para criação.
- Task permite `WhoId` para Lead e `WhatId` para objetos com Activities habilitadas, mas a validação real confirmou que o Salesforce bloqueia o uso simultâneo de Lead em `WhoId` e Empreendimento em `WhatId`.
- Não existem campos de Task/Activity compatíveis com tipo do registro, vendedor, loja ou nota.
- Não há regra de validação, Workflow ou Flow identificado sobre Task que bloqueie o desenho.
- Existe o trigger gerenciado `APXTConga4.ReassignWhatId2` em Task. Seu código não é acessível e não foi alterado; as inserções da solução foram validadas contra a automação instalada.

### Automações de Lead

- O Process Builder ativo `PB_3_Lead` envia notificação ao proprietário na criação do Lead e permanecerá inalterado.
- A regra de atribuição padrão está ativa, mas só será executada se o Apex solicitar explicitamente seu uso.
- As regras de duplicidade encontradas estão inativas e permitem DML; portanto, não oferecem proteção contra duplicação para este canal.

### Segurança pública

- Os Guest Profiles existentes não possuem permissão direta de objeto para Lead/Task nem acesso às classes novas.
- O Guest Profile de `Pesquisas` só existirá após a criação do site.
- O visitante público não receberá leitura genérica de Lead ou Task.
- O endpoint de recepção retornará somente estado funcional, nunca nome, e-mail, telefone, CPF, Id de Lead ou outro dado pessoal.
- Os sites atuais não apresentam integração reCAPTCHA ativa. Proteção contra abuso deverá ser resolvida antes da publicação em produção.

## Arquitetura proposta

### Camadas

| Camada | Responsabilidade |
|---|---|
| LWC | Interface, estado das jornadas, validação de entrada e feedback ao usuário |
| Controller Apex `with sharing` | Fachada pública mínima para os métodos `@AuraEnabled` |
| Service Apex controlado | Consultas e DML estritamente permitidos para Lead, Task e Empreendimento |
| DTOs | Contratos de entrada/saída sem exposição de SObjects |
| Security/helper | Normalização, sanitização, allowlists e validações reutilizáveis |
| Salesforce metadata | Objetos, campos, Experience Cloud, Guest Profile e manifest de rastreabilidade |

O service precisará de execução controlada em modo de sistema para permitir as operações mínimas do Guest sem conceder acesso genérico aos objetos. Isso será isolado, documentado e protegido por construção explícita de cada SObject e de cada campo autorizado.

### Contratos Apex previstos

| Operação | Entrada | Saída pública |
|---|---|---|
| `listarEmpreendimentos` | Nenhuma | Id opaco, nome, bairro e região apenas dos registros ativos |
| `criarAgendamento` | DTO de agendamento | Sucesso/erro funcional e protocolo não sensível |
| `consultarRecepcao` | CPF, e-mail ou telefone normalizados e Empreendimento | `ENCONTRADO`, `NAO_ENCONTRADO` ou `AMBIGUO`, sem dados do Lead |
| `registrarCheckin` | Token/DTO controlado da consulta e Empreendimento | Sucesso/erro funcional |
| `criarLeadRapidoECheckin` | Identificação, dados mínimos do Lead e Empreendimento | Sucesso/erro funcional |
| `registrarAvaliacao` | Vendedor, loja, nota e observação | Sucesso/erro funcional |

Os nomes finais poderão ser ajustados apenas para seguir o padrão técnico encontrado no projeto, sem alterar o contrato funcional aprovado.

## Modelo de dados proposto

### `Empreendimento__c`

| Campo/configuração | Tipo | Regra |
|---|---|---|
| `Name` | Text | Nome de exibição |
| `Codigo__c` | Text(30), External ID | Chave controlada para carga/upsert; unicidade depende da decisão registrada abaixo |
| `Bairro__c` | Text(80) | Informação exibida na seleção |
| `Regiao__c` | Text(80) | Informação exibida na seleção |
| `Ativo__c` | Checkbox | Somente ativos serão expostos ao portal |
| Allow Activities | Configuração do objeto | Mantém suporte padrão a Activities, sem substituir o lookup específico necessário ao check-in |
| External Sharing Model | Private | Evita leitura pública direta |

### Lead

| Campo | Tipo proposto | Uso |
|---|---|---|
| `CPF__c` | Text(14) | Valor formatado/controlado |
| `CPF_Normalizado__c` | Text(11) | Busca exata somente por dígitos |
| `Telefone_Normalizado__c` | Formula(Text) inicialmente | Busca por telefone existente sem backfill imediato |
| `Empreendimento__c` | Lookup(`Empreendimento__c`) | Empreendimento de interesse |
| `Regiao_Desejada__c` | Text(80) | Preferência informada |
| `Bairro_Desejado__c` | Text(80) | Preferência informada |
| `Data_Pretendida__c` | Date | Data da visita |
| `Periodo_Preferido__c` | Picklist | `Manhã` ou `Tarde` |
| `Observacoes_Agendamento__c` | Long Text Area | Observação do agendamento |
| `Origem_Formulario__c` | Picklist | Valor controlado `Comunidade Pesquisas` |

`Telefone_Normalizado__c` é uma necessidade técnica adicional ao documento de origem: sem ele, a recepção não consegue comparar de forma confiável telefones com máscara. A fórmula é adequada ao volume inicial, mas não é indexada; se houver grande volume de Leads, deverá ser convertida para texto indexável com backfill controlado.

### Activity/Task

| Campo/uso | Tipo proposto | Regra |
|---|---|---|
| `Tipo_Registro_Pesquisas__c` | Picklist em Activity | `Check-in` ou `Avaliação` |
| `Nome_Vendedor__c` | Text em Activity | Preenchido na avaliação |
| `Loja__c` | Text em Activity | Preenchido na avaliação |
| `Nota_Avaliacao__c` | Number(1,0) em Activity | Valores de 1 a 5 |
| `Estrelas_Avaliacao__c` | Formula(Text) em Activity | Representação visual da nota |
| `Description` | Campo padrão | Observação do check-in/avaliação |
| `WhoId` | Campo padrão | Lead no check-in |
| `Empreendimento__c` | Lookup em Activity | Empreendimento do check-in; fallback exigido pela restrição de `WhoId` de Lead + `WhatId` |
| `Status` | Campo padrão | `Completed` |
| `ActivityDate` | Campo padrão | Data do registro |

O lookup `Activity.Empreendimento__c` foi criado após a validação real retornar `FIELD_INTEGRITY_EXCEPTION` para Task com Lead em `WhoId` e Empreendimento em `WhatId`. A avaliação permanece sem vínculo com Lead ou Empreendimento, conforme decisão aprovada.

## Regras funcionais a implementar

### Agendamento

- Exigir ao menos um identificador: CPF, e-mail ou telefone.
- Exigir Empreendimento.
- Exigir data igual ou posterior ao dia corrente da org.
- Exigir período `Manhã` ou `Tarde`.
- Aceitar região, bairro e observação como opcionais.
- Normalizar CPF, e-mail e telefone no servidor.
- Criar o Lead somente após resolver os campos padrão obrigatórios e a política de duplicidade indicada em **Decisões necessárias**.
- Retornar mensagem de sucesso sem devolver Id ou dados do registro.

### Recepção/check-in

- Exigir ao menos um identificador e o Empreendimento.
- Consultar CPF normalizado, e-mail normalizado e telefone normalizado com parâmetros vinculados.
- Não devolver dados pessoais do Lead.
- Se houver exatamente um Lead compatível, criar Task concluída com `WhoId` e `Empreendimento__c`.
- Se não houver Lead, oferecer cadastro rápido e criar o check-in somente depois da criação válida do Lead.
- Se identificadores apontarem para Leads diferentes ou houver múltiplos resultados, retornar estado genérico `AMBIGUO` e não criar/alterar registros automaticamente.
- Prevenir duplo clique e submissão duplicada na interface.

### Avaliação

- Exigir nome do vendedor, loja e nota de 1 a 5.
- Rejeitar nota zero, vazia ou fora do intervalo no cliente e no servidor.
- Aceitar observação opcional.
- Criar Task concluída sem expor identificadores internos.
- Aplicar a política de proprietário e vínculo aprovada em **Decisões necessárias**.

## Experiência LWC

### Estrutura prevista

| Componente | Responsabilidade |
|---|---|
| `pesquisasPortal` | Container público, navegação entre jornadas e mensagens globais |
| `pesquisasHome` | Três opções iniciais |
| `pesquisasIdentificacao` | Campos reutilizáveis de CPF, e-mail e telefone |
| `pesquisasAgendamento` | Formulário e submissão de agendamento |
| `pesquisasRecepcao` | Consulta, resultado e cadastro rápido/check-in |
| `pesquisasAvaliacao` | Estrelas, vendedor, loja e observação |

O componente pai será exposto em `lightningCommunity__Page` e `lightningCommunity__Default`; os filhos permanecerão internos.

### Comportamento visual

- Mobile first, sem largura fixa e sem rolagem horizontal.
- Estados explícitos de carregamento, sucesso, erro e formulário inválido.
- Botões bloqueados durante requisições.
- Campos com labels, mensagens acessíveis, foco e navegação por teclado.
- Nenhum armazenamento de PII em `localStorage`, `sessionStorage` ou URL.
- Referência visual do plano será usada apenas como direção; nenhum ativo proprietário será copiado.
- Logo e imagens só serão adicionados se forem fornecidos/autorizados.

## Segurança e privacidade

- Guest Profile com acesso somente às classes Apex necessárias e ao componente público.
- Sem `View All`, `Modify All` ou leitura direta de Lead/Task.
- DTOs em vez de retorno de SObjects.
- Allowlist dos campos gravados.
- Normalização e validação repetidas no Apex; validação de LWC não será considerada barreira de segurança.
- SOQL estática, parâmetros vinculados e consultas limitadas.
- Mensagens genéricas para evitar enumeração de Leads.
- Sem stack trace, Id Salesforce, CPF, telefone ou e-mail em resposta de erro e logs.
- Proteção contra submissão repetida no frontend e idempotência no servidor quando aplicável.
- Avaliação de CAPTCHA/rate limiting antes de publicação em produção.

## Arquivos previstos

A lista abaixo é estimativa. Os nomes gerados pelo Experience Cloud serão confirmados pelo retrieve.

### Apex

- `force-app/main/default/classes/PesquisasPortalController.cls`
- `force-app/main/default/classes/PesquisasPortalController.cls-meta.xml`
- `force-app/main/default/classes/PesquisasPortalService.cls`
- `force-app/main/default/classes/PesquisasPortalService.cls-meta.xml`
- `force-app/main/default/classes/PesquisasPortalDTOs.cls`
- `force-app/main/default/classes/PesquisasPortalDTOs.cls-meta.xml`
- `force-app/main/default/classes/PesquisasPortalSecurity.cls`
- `force-app/main/default/classes/PesquisasPortalSecurity.cls-meta.xml`
- respectivas classes de teste, com separação ajustada ao padrão final do projeto.

### LWC

- Bundles `pesquisasPortal`, `pesquisasHome`, `pesquisasIdentificacao`, `pesquisasAgendamento`, `pesquisasRecepcao` e `pesquisasAvaliacao`.
- Testes Jest para estado, validação, sucesso, erro, loading, duplo clique e nota por estrelas.

### Objetos e campos

- Objeto e campos de `Empreendimento__c`.
- Campos de Lead listados neste plano.
- Campos de Activity listados neste plano.
- Layout de Empreendimento com todos os campos novos visíveis.

### Experience Cloud e segurança

- `Network`, `CustomSite`, `DigitalExperienceBundle` e Guest Profile gerados para `Pesquisas`.
- O nome e caminho final de cada metadado serão registrados depois do retrieve.

### Rastreabilidade

- `Manifest/package.xml`, somente com os componentes criados/alterados pela implementação.
- `works/W-019192-Comunidade-Pesquisas/arquivos-alterados-01.md`, atualizado durante a execução.
- CSV com cinco Empreendimentos, preparado mas não carregado sem autorização.

## Sequência de execução após aprovação

### Etapa 1 — Preparação e proteção do estado atual

- [x] Validar a Work `W-019192` com o script oficial: resultado `FOUND`.
- [x] Carregar os contextos obrigatórios do projeto nesta conversa.
- [x] Analisar padrões locais, automações e estado do Git.
- [x] Diagnosticar Experience Cloud, modelo de dados e Guest User na org.
- [x] Registrar este plano consolidado sem iniciar desenvolvimento.
- [x] Revalidar apenas mudanças relevantes ocorridas entre a aprovação e o início da implementação.
- [x] Registrar as respostas às decisões necessárias sem ampliar o escopo.

### Etapa 2 — Bootstrap controlado da comunidade

- [x] Criar `Pesquisas` em preview na org `MyDeveloper`, com `Build Your Own (LWR)` e acesso público.
- [x] Acompanhar o job assíncrono até conclusão real.
- [x] Recuperar os metadados gerados para o projeto.
- [x] Confirmar os nomes técnicos reais do site, Network, bundle e Guest Profile.
- [x] Manter a comunidade não publicada e não ativada.

- [x] Executar duas tentativas idênticas de criação e acompanhar os jobs até o estado terminal `Error`.
- [x] Confirmar que nenhum `Network` ou prefixo `pesquisas` foi criado parcialmente.

Comando final executado após aprovação do fallback:

```powershell
sf community create --name "Pesquisas" --template-name "Build Your Own (LWR)" --url-path-prefix "pesquisas" --target-org "MyDeveloper" --api-version 65.0 "templateParams.AuthenticationType=AUTHENTICATED_WITH_PUBLIC_ACCESS_ENABLED"
```

Jobs do template original: `08Pak00000tuhdoEAA` e `08Pak00000tudGtEAI`. Ambos retornaram erro e não criaram registros parciais. O fallback `Build Your Own (LWR)` foi autorizado pelo solicitante. Após correção do storage, o job `08Pak00000tuTG3EAM`, com `AUTHENTICATED_WITH_PUBLIC_ACCESS_ENABLED`, concluiu com `Complete`.

### Etapa 3 — Modelo de dados

- [x] Criar `Empreendimento__c`, campos, layout, compartilhamento externo privado e Activities.
- [x] Criar os campos de Lead.
- [x] Criar os campos de Activity.
- [x] Fazer deploy granular somente desses metadados em `MyDeveloper`.
- [x] Recuperar os componentes implantados e comparar local versus org.
- [ ] Validar criação manual mínima de Lead e Task sem alterar automações existentes.

### Etapa 4 — Backend Apex

- [x] Implementar DTOs sem SObjects públicos.
- [x] Implementar normalização de CPF, e-mail e telefone.
- [x] Implementar controller fino.
- [x] Implementar service com operações allowlisted.
- [x] Implementar busca sem exposição de PII e tratamento de ambiguidade.
- [x] Implementar criação de Lead, check-in e avaliação conforme decisões aprovadas.
- [x] Implementar tratamento de erro objetivo, timeout lógico e resposta vazia/inválida.
- [x] Criar testes Apex positivos, negativos, múltiplos registros e ausência de dados.
- [x] Cobrir execução em lote dos métodos internos quando aplicável.
- [x] Validar somente as classes de teste relacionadas, com cobertura mínima de 80% para Apex alterado.

### Etapa 5 — Interface LWC

- [x] Implementar o container e as três jornadas.
- [x] Implementar componente reutilizável de identificação.
- [x] Implementar carregamento de Empreendimentos ativos.
- [x] Implementar validações funcionais e acessibilidade.
- [x] Implementar loading, sucesso, erro e bloqueio de dupla submissão.
- [x] Implementar layout responsivo sem copiar ativos proprietários.
- [x] Criar e executar testes Jest relevantes.

### Etapa 6 — Integração com Experience Cloud

- [x] Inserir o LWC pai na página Home do bundle LWR.
- [x] Configurar Guest Profile somente com os acessos mínimos necessários.
- [x] Fazer deploy granular de Apex, LWC, perfil e metadados do site em `MyDeveloper`.
- [x] Confirmar que a comunidade permanece em preview.
- [ ] Validar acesso público em sessão anônima.

### Etapa 7 — Dados de referência

- [x] Preparar CSV UTF-8 com cinco Empreendimentos e códigos estáveis.
- [x] Validar o arquivo sem executar carga.
- [ ] Solicitar autorização explícita para carga.
- [ ] Após autorização, executar upsert por `Codigo__c` e registrar resultado sem dados sensíveis.

### Etapa 8 — Validação final e entrega

- [x] Executar testes Apex e Jest realmente disponíveis.
- [ ] Validar manualmente desktop, tablet, Android e iOS/navegação responsiva.
- [ ] Validar os três fluxos positivos e os principais negativos.
- [x] Validar Process Builder de Lead e trigger gerenciado de Task sem regressão.
- [ ] Validar que o público não consegue consultar Lead/Task diretamente.
- [x] Confirmar diff local versus org antes de qualquer deploy adicional.
- [x] Atualizar `Manifest/package.xml` com todos os metadados da tarefa.
- [x] Atualizar `arquivos-alterados-01.md` somente com arquivos realmente afetados.
- [ ] Entregar resultados reais e instruções de homologação.
- [ ] Solicitar autorização separada antes de publicar/ativar a comunidade.

## Registro de execução

| Bloco | Resultado | Identificador |
|---|---|---|
| Modelo de dados inicial | `Succeeded` — 21 componentes | `0Afak00000cFACTCA4` |
| Lookup Activity → Empreendimento | `Succeeded` — 1 componente | `0Afak00000cFAqnCAG` |
| Apex com testes especificados | `Succeeded` — 7 classes, 13/13 testes | `0Afak00000cF9wMCAS` |
| LWC final formatado | `Succeeded` — 6 bundles | `0Afak00000cFCCfCAO` |
| Retrieve granular de conferência | `Succeeded` — 31 componentes, 43 arquivos MDAPI | Execução temporária removida |
| Execução final de testes Apex | `Passed` — 15/15, cobertura da execução 90% | `707ak00001Qqqxp` |
| Criação do site `Microsite (LWR)` | `Error` em dois jobs; nenhum site parcial | `08Pak00000tuhdoEAA`, `08Pak00000tudGtEAI` |
| Criação do site `Build Your Own (LWR)` | `Error`; acesso público corrigido para o valor suportado, sem site parcial | `08Pak00000tu8tFEAQ`, `08Pak00000tuM1fEAE` |
| Criação final do site `Build Your Own (LWR)` | `Complete` após ajuste de storage | `08Pak00000tuTG3EAM` |
| DigitalExperienceBundle + Guest Profile | `Succeeded` — Home com `c:pesquisasPortal` e acesso Apex mínimo | `0Afak00000cFFiPCAW` |

Resultados de qualidade:

- Apex: 13/13 testes no deploy e 15/15 itens na execução final aprovados; cobertura da execução 90%.
- Cobertura: controller 81,08%; service 88,96%; security 94,23%; DTOs 100%.
- Jest: 7/7 testes aprovados em quatro suítes.
- ESLint: nenhum erro nos bundles `pesquisas*`.
- Metadata API: modelo, Apex e LWC implantados granularmente em `MyDeveloper`.
- `package.xml`: XML válido e atualizado para rastreabilidade; não foi usado como manifest de deploy.
- CSV: cinco linhas, cinco códigos únicos; nenhuma carga executada.

Estado final do Experience Cloud: `Network` `Pesquisas` em `UnderConstruction`, `CustomSite` `Pesquisas`, `DigitalExperienceBundle` `site/Pesquisas1` e Guest Profile `Pesquisas Profile`. O Salesforce gerou o prefixo técnico `pesquisasvforcesite`. A Home referencia `c:pesquisasPortal`; o Guest possui acesso a `PesquisasPortalController` e zero permissões diretas para Lead, Task e Empreendimento. A URL `/s/` permanece indisponível anonimamente enquanto o site não for publicado, conforme o portão separado deste plano.

## Testes e critérios de aceite

### Apex

- Agendamento aceita exatamente um identificador válido e rejeita nenhum identificador.
- CPF, e-mail e telefone são normalizados de forma determinística.
- Data passada e período inválido são rejeitados.
- Empreendimento inexistente ou inativo é rejeitado.
- Consulta retorna estado sem PII.
- Conflito entre identificadores retorna `AMBIGUO` sem DML.
- Check-in cria Task concluída ligada ao Lead e ao Empreendimento.
- Cadastro rápido cria Lead e Task de forma transacional.
- Falha na Task do cadastro rápido não deixa Lead parcial, se a decisão for operação atômica.
- Avaliação aceita somente nota de 1 a 5.
- Testes incluem sucesso, erro, lista vazia, múltiplos registros e volume compatível.
- Cobertura das classes alteradas igual ou superior a 80%.

### LWC/Jest

- Navegação entre as três jornadas e retorno ao início.
- Validação de ao menos um identificador.
- Data mínima, período e Empreendimento.
- Estados `loading`, sucesso, erro e ambiguidade.
- Botão desabilitado durante requisição e prevenção de duplo clique.
- Seleção de 1 a 5 estrelas e rejeição de zero.
- Nenhuma PII inserida em URL ou storage do navegador.

### Homologação manual

- Usuário público executa as três jornadas sem autenticação.
- Nenhum dado de Lead é exibido na recepção.
- Registros criados possuem proprietário interno válido.
- Process Builder de Lead continua executando como antes.
- Trigger gerenciado de Task não bloqueia `WhoId`/`Empreendimento__c`.
- Visual permanece utilizável nas larguras de 320 px, 768 px e desktop.
- Site permanece em preview até autorização de publicação.

## Riscos e mitigação

| Risco | Mitigação |
|---|---|
| Enumeração de pessoas pela resposta “encontrado” | Respostas genéricas, sem PII; considerar token de continuidade e CAPTCHA |
| Spam em endpoint público | Bloqueio de dupla submissão, validação server-side e requisito de CAPTCHA/rate limiting antes de produção |
| Duplicidade de Lead | Decisão explícita de política; busca exata normalizada; nenhuma confiança em duplicate rules inativas |
| Performance da fórmula de telefone | Adequada ao início; migrar para campo texto indexável e backfill se o volume justificar |
| Campos obrigatórios padrão de Lead | Capturar/definir Nome e Company somente conforme decisão aprovada |
| Automação gerenciada de Task | Teste real granular com `WhoId` e lookup `Empreendimento__c`; pacote gerenciado preservado |
| Proprietário inválido para Guest DML | Resolver proprietário interno pela configuração do site/decisão aprovada, sem hardcode de Id |
| IDs internos de LWR | Criar site por CLI e recuperar metadados gerados; não construir IDs manualmente |
| Alterações concorrentes na org | Retrieve e diff granular antes de cada deploy |

## Decisões necessárias na aprovação

Para não inventar regra de negócio, a aprovação deve confirmar ou corrigir os itens abaixo:

| Nº | Decisão | Recomendação técnica |
|---|---|---|
| 1 | Dados mínimos para criar Lead no agendamento e cadastro rápido | Exigir `Nome completo`; gravar em `LastName`; usar `Company = Pessoa Física` somente se esse valor for aprovado |
| 2 | Política de duplicidade no agendamento | Se houver correspondência exata não ambígua, atualizar os campos do agendamento no Lead existente; criar novo somente quando não houver correspondência |
| 3 | Regra de atribuição de Lead | Não acionar a Assignment Rule; usar o proprietário interno padrão do site, evitando regra ampla existente |
| 4 | Empreendimento obrigatório | Manter obrigatório em agendamento e recepção, conforme plano de origem |
| 5 | Visita no mesmo dia | Permitir hoje; bloquear apenas datas anteriores |
| 6 | Cadastro rápido | Operação atômica: Lead e Task são criados juntos ou ambos são revertidos |
| 7 | Avaliação | Task sem `WhoId`; `WhatId` vazio, salvo se o formulário passar a exigir Empreendimento; proprietário interno padrão do site |
| 8 | `Codigo__c` | Marcar como Unique + External ID para impedir duplicidade dos cinco registros de referência |
| 9 | Ativos visuais | Usar layout neutro do projeto até o fornecimento/autorização de logo e imagens |
| 10 | Org de desenvolvimento | Usar exclusivamente o alias `MyDeveloper`; não publicar e não atuar em produção/full sandbox |

## Fora do escopo

- Publicação ou ativação da comunidade.
- Deploy em produção, full sandbox ou outro ambiente.
- Commit, push, branch, pull request ou merge.
- Alteração das automações existentes de Lead ou do pacote gerenciado de Task.
- Alteração de Sharing Rules, Roles, OWD global, Connected Apps ou Named Credentials.
- Carga de dados sem autorização explícita.
- Uso ou reprodução de ativos proprietários do site de referência.
- Relatórios, dashboards, campanhas, conversão de Lead ou integrações externas não descritas.

## Condição para início

O desenvolvimento só começará após resposta explícita aprovando este plano e confirmando/corrigindo as dez decisões acima. Uma aprovação sem ressalvas será interpretada como aceite das recomendações registradas, incluindo deploy granular somente na org `MyDeveloper`, criação da comunidade em preview e proibição de publicação.
