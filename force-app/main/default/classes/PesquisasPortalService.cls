public without sharing class PesquisasPortalService {
    private static final String ORIGEM = 'Comunidade Pesquisas';
    private static final String EMPRESA_PADRAO = 'Pessoa Física';
    private static final String STATUS_CONCLUIDO = 'Completed';
    private static final String TIPO_CHECKIN = 'Check-in';
    private static final String TIPO_AVALIACAO = 'Avaliação';
    private static final Set<String> PERIODOS = new Set<String>{ 'Manhã', 'Tarde' };

    public static List<PesquisasPortalDTOs.EmpreendimentoOption> listarEmpreendimentos() {
        List<PesquisasPortalDTOs.EmpreendimentoOption> resultado = new List<PesquisasPortalDTOs.EmpreendimentoOption>();
        for (Empreendimento__c item : [
            SELECT Id, Name, Bairro__c, Regiao__c
            FROM Empreendimento__c
            WHERE Ativo__c = TRUE
            ORDER BY Name
            LIMIT 500
        ]) {
            PesquisasPortalDTOs.EmpreendimentoOption opcao = new PesquisasPortalDTOs.EmpreendimentoOption();
            opcao.id = item.Id;
            opcao.nome = item.Name;
            opcao.bairro = item.Bairro__c;
            opcao.regiao = item.Regiao__c;
            resultado.add(opcao);
        }
        return resultado;
    }

    public static PesquisasPortalDTOs.OperationResult criarAgendamento(
        PesquisasPortalDTOs.AgendamentoInput input
    ) {
        validarAgendamento(input);
        PesquisasPortalSecurity.IdentificacaoNormalizada identificacao =
            PesquisasPortalSecurity.normalizarIdentificacao(input);
        Empreendimento__c empreendimento = obterEmpreendimentoAtivo(input.empreendimentoId);
        List<Lead> encontrados = localizarLeads(identificacao);
        if (encontrados.size() > 1) {
            throw new PesquisasPortalSecurity.PortalException('Não foi possível identificar um cadastro único.');
        }
        Lead leadRegistro = encontrados.isEmpty()
            ? novoLead(input.nomeCompleto, identificacao)
            : encontrados[0];
        aplicarAgendamento(leadRegistro, input, identificacao, empreendimento.Id);
        upsert leadRegistro;
        return sucesso('Agendamento registrado com sucesso.');
    }

    public static PesquisasPortalDTOs.RecepcaoResult consultarRecepcao(
        PesquisasPortalDTOs.IdentificacaoInput input
    ) {
        PesquisasPortalSecurity.IdentificacaoNormalizada identificacao =
            PesquisasPortalSecurity.normalizarIdentificacao(input);
        obterEmpreendimentoAtivo(input.empreendimentoId);
        Integer quantidade = localizarLeads(identificacao).size();
        if (quantidade > 1) {
            return new PesquisasPortalDTOs.RecepcaoResult('AMBIGUO', 'Não foi possível validar o cadastro.');
        }
        if (quantidade == 1) {
            return new PesquisasPortalDTOs.RecepcaoResult('ENCONTRADO', 'Cadastro localizado. Confirme o check-in.');
        }
        return new PesquisasPortalDTOs.RecepcaoResult('NAO_ENCONTRADO', 'Complete o cadastro rápido para continuar.');
    }

    public static PesquisasPortalDTOs.OperationResult registrarCheckin(
        PesquisasPortalDTOs.IdentificacaoInput input
    ) {
        PesquisasPortalSecurity.IdentificacaoNormalizada identificacao =
            PesquisasPortalSecurity.normalizarIdentificacao(input);
        Empreendimento__c empreendimento = obterEmpreendimentoAtivo(input.empreendimentoId);
        List<Lead> encontrados = localizarLeads(identificacao);
        if (encontrados.size() != 1) {
            throw new PesquisasPortalSecurity.PortalException('Não foi possível confirmar um cadastro único.');
        }
        inserirCheckin(encontrados[0], empreendimento.Id);
        return sucesso('Check-in registrado com sucesso.');
    }

    public static PesquisasPortalDTOs.OperationResult criarLeadRapidoECheckin(
        PesquisasPortalDTOs.CadastroRapidoInput input
    ) {
        String nome = PesquisasPortalSecurity.nomeObrigatorio(input == null ? null : input.nomeCompleto);
        PesquisasPortalSecurity.IdentificacaoNormalizada identificacao =
            PesquisasPortalSecurity.normalizarIdentificacao(input);
        Empreendimento__c empreendimento = obterEmpreendimentoAtivo(input.empreendimentoId);
        Savepoint pontoRestauracao = Database.setSavepoint();
        try {
            Lead leadRegistro = resolverLeadCadastroRapido(nome, identificacao, empreendimento.Id);
            inserirCheckin(leadRegistro, empreendimento.Id);
            return sucesso('Cadastro e check-in registrados com sucesso.');
        } catch (Exception erro) {
            Database.rollback(pontoRestauracao);
            throw erro;
        }
    }

    public static PesquisasPortalDTOs.OperationResult registrarAvaliacao(
        PesquisasPortalDTOs.AvaliacaoInput input
    ) {
        if (input == null || input.nota == null || input.nota < 1 || input.nota > 5) {
            throw new PesquisasPortalSecurity.PortalException('Selecione uma nota de 1 a 5.');
        }
        Task avaliacao = new Task(
            Subject = 'Avaliação - Comunidade Pesquisas',
            Status = STATUS_CONCLUIDO,
            ActivityDate = Date.today(),
            OwnerId = resolverProprietarioPortal(),
            Tipo_Registro_Pesquisas__c = TIPO_AVALIACAO,
            Nome_Vendedor__c = campoObrigatorio(input.nomeVendedor, 120, 'Informe o nome do vendedor.'),
            Loja__c = campoObrigatorio(input.loja, 120, 'Informe a loja.'),
            Nota_Avaliacao__c = input.nota,
            Description = PesquisasPortalSecurity.textoSeguro(input.observacoes, 32000)
        );
        insert avaliacao;
        return sucesso('Avaliação registrada com sucesso.');
    }

    private static void validarAgendamento(PesquisasPortalDTOs.AgendamentoInput input) {
        if (input == null) {
            throw new PesquisasPortalSecurity.PortalException('Informe os dados do agendamento.');
        }
        PesquisasPortalSecurity.nomeObrigatorio(input.nomeCompleto);
        if (input.dataPretendida == null || input.dataPretendida < Date.today()) {
            throw new PesquisasPortalSecurity.PortalException('Informe uma data igual ou posterior a hoje.');
        }
        if (!PERIODOS.contains(input.periodo)) {
            throw new PesquisasPortalSecurity.PortalException('Informe o período da visita.');
        }
    }

    private static Lead novoLead(
        String nomeCompleto,
        PesquisasPortalSecurity.IdentificacaoNormalizada identificacao
    ) {
        return new Lead(
            LastName = PesquisasPortalSecurity.nomeObrigatorio(nomeCompleto),
            Company = EMPRESA_PADRAO,
            LeadSource = 'Web',
            OwnerId = resolverProprietarioPortal(),
            Email = identificacao.email,
            Phone = identificacao.telefone,
            CPF__c = identificacao.cpf,
            CPF_Normalizado__c = identificacao.cpf
        );
    }

    private static void aplicarAgendamento(
        Lead leadRegistro,
        PesquisasPortalDTOs.AgendamentoInput input,
        PesquisasPortalSecurity.IdentificacaoNormalizada identificacao,
        Id empreendimentoId
    ) {
        preencherIdentificacaoAusente(leadRegistro, identificacao);
        leadRegistro.Empreendimento__c = empreendimentoId;
        leadRegistro.Regiao_Desejada__c = PesquisasPortalSecurity.textoSeguro(input.regiao, 80);
        leadRegistro.Bairro_Desejado__c = PesquisasPortalSecurity.textoSeguro(input.bairro, 80);
        leadRegistro.Data_Pretendida__c = input.dataPretendida;
        leadRegistro.Periodo_Preferido__c = input.periodo;
        leadRegistro.Observacoes_Agendamento__c = PesquisasPortalSecurity.textoSeguro(input.observacoes, 32000);
        leadRegistro.Origem_Formulario__c = ORIGEM;
    }

    private static void preencherIdentificacaoAusente(
        Lead leadRegistro,
        PesquisasPortalSecurity.IdentificacaoNormalizada identificacao
    ) {
        if (String.isBlank(leadRegistro.CPF_Normalizado__c) && String.isNotBlank(identificacao.cpf)) {
            leadRegistro.CPF__c = identificacao.cpf;
            leadRegistro.CPF_Normalizado__c = identificacao.cpf;
        }
        if (String.isBlank(leadRegistro.Email) && String.isNotBlank(identificacao.email)) {
            leadRegistro.Email = identificacao.email;
        }
        if (String.isBlank(leadRegistro.Phone) && String.isNotBlank(identificacao.telefone)) {
            leadRegistro.Phone = identificacao.telefone;
        }
    }

    private static Lead resolverLeadCadastroRapido(
        String nome,
        PesquisasPortalSecurity.IdentificacaoNormalizada identificacao,
        Id empreendimentoId
    ) {
        List<Lead> encontrados = localizarLeads(identificacao);
        if (encontrados.size() > 1) {
            throw new PesquisasPortalSecurity.PortalException('Não foi possível identificar um cadastro único.');
        }
        if (!encontrados.isEmpty()) {
            return encontrados[0];
        }
        Lead leadRegistro = novoLead(nome, identificacao);
        leadRegistro.Empreendimento__c = empreendimentoId;
        leadRegistro.Origem_Formulario__c = ORIGEM;
        insert leadRegistro;
        return leadRegistro;
    }

    private static List<Lead> localizarLeads(
        PesquisasPortalSecurity.IdentificacaoNormalizada identificacao
    ) {
        List<String> filtros = new List<String>();
        Map<String, Object> binds = new Map<String, Object>();
        adicionarFiltro(filtros, binds, 'CPF_Normalizado__c', 'cpf', identificacao.cpf);
        adicionarFiltro(filtros, binds, 'Email', 'email', identificacao.email);
        adicionarFiltro(filtros, binds, 'Telefone_Normalizado__c', 'telefone', identificacao.telefone);
        String consulta = 'SELECT Id, OwnerId, CPF__c, CPF_Normalizado__c, Email, Phone ' +
            'FROM Lead WHERE ' + String.join(filtros, ' OR ') + ' LIMIT 3';
        return Database.queryWithBinds(consulta, binds, AccessLevel.SYSTEM_MODE);
    }

    private static void adicionarFiltro(
        List<String> filtros,
        Map<String, Object> binds,
        String campo,
        String chave,
        String valor
    ) {
        if (String.isNotBlank(valor)) {
            filtros.add(campo + ' = :' + chave);
            binds.put(chave, valor);
        }
    }

    private static Empreendimento__c obterEmpreendimentoAtivo(Id empreendimentoId) {
        if (empreendimentoId == null) {
            throw new PesquisasPortalSecurity.PortalException('Selecione o empreendimento.');
        }
        List<Empreendimento__c> registros = [
            SELECT Id
            FROM Empreendimento__c
            WHERE Id = :empreendimentoId AND Ativo__c = TRUE
            LIMIT 1
        ];
        if (registros.isEmpty()) {
            throw new PesquisasPortalSecurity.PortalException('O empreendimento selecionado não está disponível.');
        }
        return registros[0];
    }

    private static void inserirCheckin(Lead leadRegistro, Id empreendimentoId) {
        insert new Task(
            Subject = 'Check-in - Comunidade Pesquisas',
            Status = STATUS_CONCLUIDO,
            ActivityDate = Date.today(),
            OwnerId = leadRegistro.OwnerId,
            WhoId = leadRegistro.Id,
            Empreendimento__c = empreendimentoId,
            Tipo_Registro_Pesquisas__c = TIPO_CHECKIN
        );
    }

    private static Id resolverProprietarioPortal() {
        List<Site> sites = [
            SELECT GuestRecordDefaultOwnerId
            FROM Site
            WHERE MasterLabel = 'Pesquisas'
            LIMIT 1
        ];
        if (!sites.isEmpty() && sites[0].GuestRecordDefaultOwnerId != null) {
            return sites[0].GuestRecordDefaultOwnerId;
        }
        if (Test.isRunningTest()) {
            return UserInfo.getUserId();
        }
        throw new PesquisasPortalSecurity.PortalException('O portal ainda não possui proprietário interno configurado.');
    }

    private static String campoObrigatorio(String valor, Integer limite, String mensagem) {
        String resultado = PesquisasPortalSecurity.textoSeguro(valor, limite);
        if (String.isBlank(resultado)) {
            throw new PesquisasPortalSecurity.PortalException(mensagem);
        }
        return resultado;
    }

    private static PesquisasPortalDTOs.OperationResult sucesso(String mensagem) {
        return new PesquisasPortalDTOs.OperationResult(true, mensagem);
    }
}
