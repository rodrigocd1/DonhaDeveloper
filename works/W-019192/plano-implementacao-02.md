# Plano de implementação 02 — Check-in do Corretor por QR Code

- Agente/modelo: Codex / GPT-5
- Configuração: agente sênior Salesforce; Work `W-019192`; projeto API 65.0; org alvo de desenvolvimento `MyDeveloper`, resolvida para o alias `Donha_Developer`; implementação local e validação check-only; sem deploy, commit ou push
- Data de início: 2026-06-19
- Objetivo: implantar na comunidade LWR pública Pesquisas uma jornada independente de check-in do corretor, acessível por QR Code e CTA, com CPF, loja configurável, confirmação visual e persistência segura.
- Motivo: disponibilizar check-in rastreável por loja sem alterar as jornadas existentes de Agendamento, Recepção e Avaliação e sem expor dados pessoais ao usuário Guest.

## Estado e trava de execução

- [x] Validar a Work `W-019192` pelo script oficial; resultado `FOUND`.
- [x] Confirmar que o repositório estava sem alterações locais antes da criação deste plano.
- [x] Diagnosticar o projeto e a org sem retrieve e sem alterar metadata.
- [x] Identificar arquitetura, metadados existentes, rota, perfil Guest e riscos.
- [x] Elaborar este plano detalhado e a rastreabilidade correspondente.
- [x] Receber confirmação explícita do Rodrigo para iniciar a implementação.
- [ ] Receber autorização específica antes de qualquer branch, commit, push ou deploy não abrangido pela confirmação.

Implementação local autorizada pelo Rodrigo em 2026-06-19.

## Diagnóstico consolidado

| Item | Resultado |
|---|---|
| Work | `W-019192` validada com resultado `FOUND` |
| Branch atual | `main`, protegida para commit pelas regras do projeto |
| Estado inicial do Git | Limpo; nenhum arquivo modificado antes deste plano |
| Projeto | Salesforce DX, API 65.0, package directory `force-app` |
| Org alvo | Configuração `MyDeveloper`; alias conectado `Donha_Developer` |
| Source tracking | Indisponível na org; `deploy preview` não consegue comparar conflitos |
| Comunidade | Network `Pesquisas` existente |
| Status da Network | `Live` após ativação autorizada; estado inicial `UnderConstruction` |
| Site LWR | Ativo e com acesso público habilitado |
| ExperienceBundle | `site/Pesquisas1` |
| URL base LWR validada | `https://sfdonha-dev-ed.my.site.com/pesquisas` |
| URL legada adicional | `https://sfdonha-dev-ed.my.site.com/pesquisasvforcesite`; não deve ser usada pela nova rota LWR |
| Componente raiz da Home | `pesquisasPortal` |
| Componente das opções da Home | `pesquisasHome` |
| CSS atual | Azul `#173f73`, amarelo `#f6b51b`, cards brancos, bordas de `1rem` e layout responsivo |
| Apex atual | `PesquisasPortalController`, `PesquisasPortalService`, `PesquisasPortalSecurity` e `PesquisasPortalDTOs` |
| Check-in atual | Jornada `pesquisasRecepcao`, que identifica `Lead` e grava `Task` relacionada a Lead e Empreendimento |
| CPF atual | `Lead.CPF__c`, `Lead.CPF_Normalizado__c` e validação algorítmica reutilizável em `PesquisasPortalSecurity` |
| Cadastro de loja atual | Não existe objeto mestre de lojas adequado à feature; há somente `Activity.Loja__c`, campo texto usado em Avaliação |
| Objeto `CheckIn__c` da org | Existe, mas pertence a outro domínio: exige Conta, identificador de posto e geolocalização; não é compatível com o check-in do corretor |
| Outros objetos com “loja/PDV” | `Venda_Mensal_Loja__c`, `Logistica_PDV__c` e `Material_PDV__c`; não representam cadastro mestre de lojas para a comunidade |
| Static Resource de QR Code | Não existe |
| CSP/Named Credential para QR | Não são necessários na estratégia local proposta |
| Guest User | Usuário ativo com perfil `Pesquisas Profile`; a classe `PesquisasPortalController` já está liberada |
| Permissões Guest atuais | Nenhuma permissão de objeto explícita para Lead, Task, Empreendimento ou CheckIn no perfil consultado; o fluxo atual usa serviço controlado em Apex |

## Decisões técnicas propostas

### 1. Isolamento da nova jornada

A nova feature não deve alterar o comportamento de `pesquisasRecepcao`, `registrarCheckin` ou `criarLeadRapidoECheckin`.

Justificativa:

- o fluxo atual exige Lead e Empreendimento;
- a nova tela exige somente CPF e Loja;
- criar ou localizar Lead sem nome ou regra de vínculo do corretor inventaria regra de negócio;
- reutilizar o `CheckIn__c` legado exigiria preencher campos obrigatórios de outro processo;
- o isolamento reduz regressão nas três jornadas públicas já existentes.

### 2. Modelo de dados recomendado

Criar `Loja__c` como cadastro mestre mínimo:

| Propriedade/campo | Definição proposta |
|---|---|
| Name | Text(80), nome da loja |
| `Codigo__c` | Text(80), obrigatório, Unique e External ID; chave estável da URL |
| `Endereco__c` | Text(255), obrigatório |
| `Ativa__c` | Checkbox, default `true` |
| `Loja_Padrao__c` | Checkbox, default `false` |
| `Ordem_Exibicao__c` | Number(3,0), usado na ordenação |
| Sharing interno | Public Read Only |
| Sharing externo | Public Read Only, pois nome/endereço/código são dados públicos |

Criar `Checkin_Corretor__c` como objeto transacional mínimo:

| Propriedade/campo | Definição proposta |
|---|---|
| Name | Auto Number `CHK-{000000}` |
| `CPF_Normalizado__c` | Text(11), obrigatório; somente dígitos |
| `Loja__c` | Lookup obrigatório para `Loja__c` |
| `Data_Hora_Checkin__c` | DateTime obrigatório, preenchido no servidor com `System.now()` |
| Sharing interno | Private |
| Sharing externo | Private |

Não serão criados campos duplicados de CPF, status fixo, origem, snapshot de loja ou observação técnica sem nova solicitação. A confirmação deste plano aprova a criação desses dois objetos e do conjunto mínimo de campos acima.

### 3. Consistência da loja padrão

- Deve existir exatamente uma loja ativa com `Loja_Padrao__c = true`.
- A carga será validada antes da publicação.
- Ausência ou duplicidade de loja padrão deve produzir erro técnico seguro, sem selecionar silenciosamente uma configuração ambígua.
- Código de loja ausente na URL carrega a loja padrão.
- Código inexistente ou inativo carrega a loja padrão e mostra aviso discreto.
- A confirmação do check-in sempre revalida a loja no backend.

### 4. Arquitetura Apex

Preservar o padrão Controller, Service, Security e DTO existente:

- adicionar ao `PesquisasPortalController` apenas endpoints finos para loja padrão, lojas ativas e confirmação do check-in;
- criar `PesquisasCorretorCheckinService` para concentrar consulta de lojas e criação de `Checkin_Corretor__c` sem aumentar o serviço das jornadas atuais;
- ampliar `PesquisasPortalDTOs` com DTOs mínimos de loja e entrada de check-in;
- reutilizar a validação algorítmica de CPF em `PesquisasPortalSecurity`, expondo somente um método objetivo de normalização/validação para CPF obrigatório;
- retornar somente código, nome e endereço de loja e uma mensagem de resultado;
- não retornar CPF, IDs internos, stack trace ou detalhes de exceção;
- não executar SOQL ou DML em loop;
- manter os métodos pequenos e orientados a testes.

Endpoints previstos:

```apex
@AuraEnabled(cacheable=true)
public static PesquisasPortalDTOs.LojaOption obterLojaPadrao()

@AuraEnabled(cacheable=true)
public static List<PesquisasPortalDTOs.LojaOption> listarLojasAtivas()

@AuraEnabled
public static PesquisasPortalDTOs.OperationResult confirmarCheckinCorretor(
    PesquisasPortalDTOs.CheckinCorretorInput input
)
```

### 5. Segurança Guest e LGPD

- liberar Read/Create em `Checkin_Corretor__c`, dependência obrigatória da plataforma, e Read em `Loja__c` no `Pesquisas Profile`;
- liberar somente FLS dos campos necessários;
- não conceder Edit, Delete, View All ou Modify All em `Checkin_Corretor__c`;
- impedir acesso aos registros de check-in por compartilhamento externo Private e ausência de endpoint de consulta;
- manter `Checkin_Corretor__c` com compartilhamento externo Private;
- manter a chamada pública na classe já autorizada `PesquisasPortalController`;
- criar Permission Set mínimo para validação do DML em modo usuário e eventual acesso interno, sem atribuição permanente automática;
- consultar o catálogo público de lojas sob sharing e executar o DML transacional em modo usuário;
- normalizar e validar CPF exclusivamente no servidor antes de persistir;
- não incluir CPF na URL, mensagens, logs ou retorno Apex;
- incluir bloqueio de duplo clique e campo honeypot sem persistência;
- não criar regra de deduplicação temporal sem regra de negócio aprovada.

### 6. Componentes LWC

Criar somente os componentes necessários:

| Componente | Responsabilidade |
|---|---|
| `pesquisasCorretorCheckinCard` | Seção inferior da Home com loja padrão, endereço, QR Code e CTA |
| `pesquisasCorretorCheckinPage` | Tela pública com CPF, loja, endereço, troca de loja, confirmação e feedback |
| `pesquisasQrCode` | Encapsular o carregamento da biblioteca local e renderizar a URL |

Alterar `pesquisasHome` somente para inserir a nova seção abaixo dos três cards atuais. `pesquisasPortal`, Agendamento, Recepção e Avaliação não terão comportamento alterado.

O seletor de lojas permanecerá dentro de `pesquisasCorretorCheckinPage`; um quarto LWC só será criado se a implementação demonstrar necessidade real de isolamento.

### 7. Rota e navegação

- Criar página pública LWR `Check-in do Corretor` no bundle `site/Pesquisas1`.
- Usar rota relativa `/checkin-corretor` dentro do base path da comunidade.
- URL de desenvolvimento esperada: `https://sfdonha-dev-ed.my.site.com/pesquisas/checkin-corretor`.
- Parâmetro permitido: `loja=<Codigo__c>`.
- URL inicial esperada: `/pesquisas/checkin-corretor?loja=LOJA-MORUMBI`.
- Calcular a URL com o base path da comunidade; não hardcodar domínio ou prefixo de ambiente.
- CTA e QR Code devem usar exatamente a mesma URL.

### 8. QR Code

- Usar biblioteca JavaScript local em Static Resource.
- Não usar CDN, serviço externo, Named Credential ou CSP Trusted Site.
- Validar licença permissiva e registrar versão/origem antes de adicionar a dependência.
- Codificar somente a URL pública com o código da loja.
- Tratar falha de carregamento com mensagem segura e manter o CTA funcional.
- Validar leitura física do QR Code em dispositivo Android e iOS.

### 9. Massa de dados

- Revalidar a lista de lojas na fonte pública imediatamente antes da carga, pois o arquivo de referência é um snapshot.
- Carregar todas as lojas ativas validadas, não apenas cinco registros parciais.
- Marcar `LOJA-MORUMBI` como única loja padrão, com endereço `Av. Giovanni Gronchi, 2967`.
- Registrar a massa em arquivo JSON versionado, sem criar script auxiliar.
- Criar cinco check-ins fictícios somente na org de desenvolvimento e somente após o deploy, usando CPFs sintéticos válidos; nunca criar massa transacional em produção sem autorização explícita.

## Etapas detalhadas de execução

### Fase 1 — Proteção do estado atual

- [x] Confirmar novamente branch e `git status` imediatamente antes da implementação.
- [x] Parar se houver alteração de outra pessoa em arquivos do escopo.
- [x] Fazer retrieve granular dos componentes existentes para diretório temporário separado.
- [x] Comparar org e local para `site/Pesquisas1`, Network, CustomSite, perfil Guest, Apex e LWCs do portal.
- [x] Remover o diretório temporário ao concluir a comparação.
- [x] Parar e informar se a org tiver versão divergente que possa ser sobrescrita.

### Fase 2 — Modelo de dados e permissões

- [x] Criar metadata de `Loja__c` e seus cinco campos customizados.
- [x] Criar metadata de `Checkin_Corretor__c` e seus três campos customizados.
- [x] Configurar sharing interno/externo conforme este plano.
- [x] Alterar somente o `Pesquisas Profile` com CRUD/FLS mínimo.
- [x] Manter registros de check-in com sharing externo Private e sem endpoint de consulta.
- [x] Atualizar `Manifest/package.xml` com cada metadata criada ou alterada.

### Fase 3 — Backend

- [x] Criar `PesquisasCorretorCheckinService` seguindo o padrão atual.
- [x] Adicionar os três endpoints delegadores ao `PesquisasPortalController`.
- [x] Adicionar DTOs mínimos em `PesquisasPortalDTOs`.
- [x] Reutilizar e ajustar a validação de CPF em `PesquisasPortalSecurity` sem duplicar algoritmo.
- [x] Validar loja ativa, loja padrão, payload, honeypot e DML em modo usuário.
- [x] Criar o check-in com CPF normalizado e horário do servidor.
- [x] Garantir mensagens seguras de sucesso e erro.
- [x] Não alterar os métodos de Agendamento, Recepção ou Avaliação.

### Fase 4 — Frontend e QR Code

- [x] Criar `pesquisasCorretorCheckinCard` no padrão visual atual.
- [x] Criar `pesquisasCorretorCheckinPage` com CPF vazio, loja, endereço, troca e confirmação.
- [x] Criar `pesquisasQrCode` com fallback acessível.
- [x] Adicionar Static Resource de QR Code somente após validar licença.
- [x] Alterar `pesquisasHome` para inserir a seção abaixo dos cards existentes.
- [x] Manter os três cards e eventos atuais sem alteração funcional.
- [x] Aplicar máscara visual de CPF sem enviar máscara ao backend.
- [x] Tratar loading, sucesso, erro, falha de QR e duplo clique.
- [x] Manter foco visível, labels, `aria-live`, texto alternativo e navegação por teclado.
- [x] Validar responsividade sem scroll horizontal.

### Fase 5 — Experience Cloud

- [x] Criar a view LWR da página `Check-in do Corretor`.
- [x] Criar a route LWR com prefixo `checkin-corretor` e acesso público.
- [x] Inserir somente `pesquisasCorretorCheckinPage` na nova view.
- [x] Não alterar tema, header, footer ou páginas não relacionadas.
- [x] Publicar/ativar a comunidade após autorização explícita do Rodrigo.
- [x] Validar que a rota usa `/pesquisas`, não o site legado `/pesquisasvforcesite`.

### Fase 6 — Dados

- [x] Revalidar a relação e os endereços das lojas na fonte pública.
- [x] Gerar arquivo JSON com todas as lojas validadas.
- [x] Carregar as lojas na org de desenvolvimento.
- [x] Validar unicidade de `Codigo__c` e existência de uma única loja padrão ativa.
- [x] Criar cinco check-ins fictícios na org de desenvolvimento.
- [x] Não criar massa transacional em produção.

### Fase 7 — Testes automatizados

- [x] Testar loja padrão única, ausente e duplicada.
- [x] Testar listagem apenas de lojas ativas e ordenação.
- [x] Testar código existente, inexistente e inativo.
- [x] Testar CPF válido, vazio, inválido, mascarado e normalizado.
- [x] Testar criação de check-in e campos persistidos.
- [x] Testar ausência de retorno de CPF e de detalhes técnicos.
- [x] Testar múltiplas lojas e ausência de dados.
- [x] Testar honeypot e payload inválido.
- [x] Atualizar teste do Controller para os novos endpoints e exceções seguras.
- [x] Manter cobertura Apex mínima de 80% para o Apex novo e para as linhas adicionadas ao Apex existente.
- [x] Atualizar Jest de `pesquisasHome` preservando as três jornadas atuais.
- [x] Criar Jest para card, página e QR Code: carregamento, navegação, seleção, submit, sucesso, erro e bloqueio de duplo clique.
- [x] Executar lint, Jest relacionado e validação check-only com testes Apex específicos.

### Fase 8 — Validação manual

- [x] Validar Home pública em janela anônima.
- [x] Validar Loja Morumbi e endereço padrão.
- [x] Validar CTA e QR Code apontando para a mesma URL.
- [x] Validar troca de loja e atualização do endereço.
- [x] Validar erro amigável sem CPF e com CPF inválido.
- [x] Validar sucesso em verde e criação de um único registro por clique.
- [x] Validar que o Guest não consegue consultar registros de check-in.
- [x] Validar console do navegador sem erro técnico ou dado sensível.
- [x] Validar larguras de 360px, 390px, 414px, 768px e 1366px.
- [ ] Validar QR Code real em Android e iOS.
- [x] Validar que Agendamento, Recepção e Avaliação continuam funcionando.

### Fase 9 — Deploy granular

- [x] Revisar diff e confirmar que não há arquivo fora do plano.
- [x] Fazer deploy somente dos objetos/campos, Apex, LWCs, Static Resource, perfil, rota/view e dados aprovados.
- [x] Não usar o `package.xml` completo no deploy.
- [x] Executar somente `PesquisasPortalControllerTest`, `PesquisasPortalSecurityTest` e o novo teste do serviço em validação check-only.
- [x] Confirmar cobertura mínima de 80% do Apex novo e das linhas adicionadas ao Apex existente.
- [x] Registrar resultado real da validação check-only e dos testes: job final `0Afak00000cH9llCAC`, 53/53 componentes e 14/14 testes.
- [x] Atualizar checklist e `arquivos-alterados-02.md` com o conjunto efetivo.
- [x] Não fazer deploy em produção ou full sandbox sem pedido explícito.

## Arquivos previstos

### Criar

```text
force-app/main/default/objects/Loja__c/Loja__c.object-meta.xml
force-app/main/default/objects/Loja__c/fields/Codigo__c.field-meta.xml
force-app/main/default/objects/Loja__c/fields/Endereco__c.field-meta.xml
force-app/main/default/objects/Loja__c/fields/Ativa__c.field-meta.xml
force-app/main/default/objects/Loja__c/fields/Loja_Padrao__c.field-meta.xml
force-app/main/default/objects/Loja__c/fields/Ordem_Exibicao__c.field-meta.xml
force-app/main/default/objects/Checkin_Corretor__c/Checkin_Corretor__c.object-meta.xml
force-app/main/default/objects/Checkin_Corretor__c/fields/CPF_Normalizado__c.field-meta.xml
force-app/main/default/objects/Checkin_Corretor__c/fields/Loja__c.field-meta.xml
force-app/main/default/objects/Checkin_Corretor__c/fields/Data_Hora_Checkin__c.field-meta.xml
force-app/main/default/classes/PesquisasCorretorCheckinService.cls
force-app/main/default/classes/PesquisasCorretorCheckinService.cls-meta.xml
force-app/main/default/classes/PesquisasCorretorCheckinServiceTest.cls
force-app/main/default/classes/PesquisasCorretorCheckinServiceTest.cls-meta.xml
force-app/main/default/lwc/pesquisasCorretorCheckinCard/*
force-app/main/default/lwc/pesquisasCorretorCheckinPage/*
force-app/main/default/lwc/pesquisasQrCode/*
force-app/main/default/staticresources/qrcode.min.js
force-app/main/default/staticresources/qrcode.resource-meta.xml
force-app/main/default/digitalExperiences/site/Pesquisas1/sfdc_cms__route/Checkin_Corretor/*
force-app/main/default/digitalExperiences/site/Pesquisas1/sfdc_cms__view/checkinCorretor/*
data/lojas-pesquisas.json
```

Os nomes das pastas de route/view serão confirmados pelo metadata gerado para evitar identificadores LWR inventados.

### Alterar

```text
force-app/main/default/classes/PesquisasPortalController.cls
force-app/main/default/classes/PesquisasPortalControllerTest.cls
force-app/main/default/classes/PesquisasPortalDTOs.cls
force-app/main/default/classes/PesquisasPortalSecurity.cls
force-app/main/default/classes/PesquisasPortalSecurityTest.cls
force-app/main/default/lwc/pesquisasHome/pesquisasHome.html
force-app/main/default/lwc/pesquisasHome/pesquisasHome.css
force-app/main/default/lwc/pesquisasHome/__tests__/pesquisasHome.test.js
force-app/main/default/profiles/Pesquisas Profile.profile-meta.xml
Manifest/package.xml
works/W-019192/plano-implementacao-02.md
works/W-019192/arquivos-alterados-02.md
```

### Não alterar

```text
force-app/main/default/lwc/pesquisasAgendamento/*
force-app/main/default/lwc/pesquisasRecepcao/*
force-app/main/default/lwc/pesquisasAvaliacao/*
force-app/main/default/classes/PesquisasPortalService.cls
force-app/main/default/objects/Lead/*
```

## Comandos de validação previstos

Executar somente após implementação e conforme os componentes efetivamente alterados:

```powershell
npm run lint
npm run test:unit -- --runInBand --findRelatedTests force-app/main/default/lwc/pesquisasHome force-app/main/default/lwc/pesquisasCorretorCheckinCard force-app/main/default/lwc/pesquisasCorretorCheckinPage force-app/main/default/lwc/pesquisasQrCode
sf apex run test --target-org MyDeveloper --tests PesquisasPortalControllerTest,PesquisasPortalSecurityTest,PesquisasCorretorCheckinServiceTest --code-coverage --result-format human --wait 30
```

O deploy, se autorizado, deve usar `--source-dir` por componente ou uma lista explícita de metadata. Nunca usar `Manifest/package.xml` inteiro.

## Riscos e contenções

| Risco | Contenção |
|---|---|
| Branch `main` protegida | Não criar commit; pedir orientação se Git fizer parte da execução |
| Org sem source tracking | Retrieve granular para diretório temporário e diff antes de editar |
| Network `UnderConstruction` | Tratar publicação/ativação como etapa separada e autorizada |
| Dois Sites com o mesmo MasterLabel | Usar o Site LWR `Pesquisas1` e base path `/pesquisas` |
| CPF é dado pessoal | Persistir uma única versão normalizada, impedir leitura Guest e não logar/retornar |
| Endpoint público sujeito a abuso | CRUD/FLS mínimo, honeypot, bloqueio de duplo clique e validação server-side |
| `CheckIn__c` legado confundido com a feature | Não reutilizar nem alterar esse objeto |
| Regressão no check-in atual | Não alterar `pesquisasRecepcao` nem `PesquisasPortalService` |
| Biblioteca de QR Code | Validar licença/versão, manter local e oferecer CTA como fallback |
| ExperienceBundle gerar diff amplo | Criar somente route/view e revisar diff granular antes do deploy |
| Lista de lojas desatualizada | Revalidar fonte antes da carga e parar se não for possível confirmar a lista completa |
| Mais de uma loja padrão | Validar carga e bloquear configuração ambígua no backend |

## Resultado da execução

- [x] Validação check-only granular concluída na org `MyDeveloper`: job final `0Afak00000cH9llCAC`.
- [x] Metadata validada: 53/53 componentes, sem erro.
- [x] Apex validado: 14/14 testes, sem erro; serviço novo com 91,3% de cobertura.
- [x] Frontend validado: 4 suítes Jest e 8 testes aprovados; ESLint e Prettier aprovados.
- [x] JSON, XML e `git diff --check` aprovados.
- [x] Deploy, carga das lojas, massa fictícia, publicação e validação em navegador executados após autorização específica.
- [x] Deploy principal concluído: job `0Afak00000cGrfCCAS`, 53/53 componentes e 14/14 testes.
- [x] Regra Guest `Loja__c.Lojas_Ativas_Pesquisas_Guest` criada após diagnóstico de compartilhamento seguro.
- [x] Catálogo final: 18 lojas, 18 códigos únicos e uma única loja padrão ativa.
- [x] Massa final: cinco check-ins fictícios; o registro temporário da validação Guest foi removido.
- [x] Publicação final solicitada no job `08Pak00000tzGt1EAE` e confirmada pelas URLs públicas.
- [x] Network `Pesquisas` ativada como `Live`: deploy `0Afak00000cHGaLCAW`.
- [x] Guest validado com consulta das lojas, criação real de check-in e ausência de consulta pública dos registros.
- [x] Responsividade validada sem overflow em 360px, 390px, 414px, 768px e 1366px.
- [ ] Leitura física do QR Code em aparelhos Android e iOS depende de dispositivos externos e permanece pendente.

## Rollback

- [ ] Remover a seção de check-in do corretor de `pesquisasHome`.
- [ ] Remover/despublicar route e view `/checkin-corretor`.
- [ ] Remover acesso Guest adicionado no `Pesquisas Profile`.
- [ ] Despublicar os três LWCs da feature.
- [ ] Reverter endpoints, DTOs e ajustes de segurança adicionados.
- [ ] Remover o Static Resource de QR Code.
- [ ] Preservar registros transacionais até decisão explícita de retenção/backup.
- [ ] Remover objetos/campos somente em ambiente controlado e com autorização específica.
- [ ] Nunca executar destructive changes ou excluir dados em produção automaticamente.

## Ordem de entrega

Sem autorização para commits. Se o Rodrigo solicitar Git posteriormente, a sequência lógica será:

1. documentação e diagnóstico;
2. modelo de dados e permissões;
3. Apex e testes;
4. LWC e testes;
5. QR Code e Experience Cloud;
6. massa de lojas;
7. validação final e rastreabilidade.

## Critérios de aceite

- [x] A Home pública mantém as três jornadas existentes e exibe a nova seção inferior.
- [x] Loja Morumbi e `Av. Giovanni Gronchi, 2967` são carregados do Salesforce.
- [x] CTA e QR Code abrem a mesma página e a mesma loja.
- [x] A página abre com CPF vazio e loja válida selecionada.
- [x] A troca de loja atualiza nome e endereço.
- [x] CPF é obrigatório, normalizado e validado algoritmicamente.
- [x] Check-in válido cria `Checkin_Corretor__c` com loja e horário do servidor.
- [x] Sucesso é exibido em verde e erros são amigáveis.
- [x] Guest executa o fluxo sem obter leitura dos check-ins.
- [x] CPF não aparece em URL, logs, retorno ou mensagem de sucesso.
- [x] Não há chamada externa para gerar QR Code.
- [ ] Interface funciona em Android, iOS, tablet e desktop sem scroll horizontal.
- [x] Testes Apex do escopo atingem pelo menos 80% de cobertura.
- [x] Jest, lint e testes em navegador do escopo passam.
- [x] Agendamento, Recepção e Avaliação permanecem funcionais.
- [x] `Manifest/package.xml` contém os componentes alterados, mas não é usado como deploy completo.
- [x] Nenhum deploy em produção/full sandbox, commit ou push é executado sem autorização explícita.

## Confirmação necessária

A confirmação para execução deve aprovar conjuntamente:

1. criação de `Loja__c` e `Checkin_Corretor__c` no modelo mínimo descrito;
2. não reutilização do `CheckIn__c` legado nem do fluxo atual `Lead + Task`;
3. uso de biblioteca de QR Code local após validação de licença;
4. alteração mínima do `Pesquisas Profile`;
5. carga completa de lojas após revalidação da fonte e cinco check-ins fictícios somente em desenvolvimento;
6. implementação local sem branch, commit, push ou deploy automático fora do que for explicitamente autorizado.
