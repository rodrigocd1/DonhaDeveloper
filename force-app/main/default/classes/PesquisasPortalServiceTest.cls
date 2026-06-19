@IsTest
private class PesquisasPortalServiceTest {
    @TestSetup
    static void criarDados() {
        insert new Empreendimento__c(
            Name = 'Residencial Teste',
            Codigo__c = 'TESTE-001',
            Bairro__c = 'Centro',
            Regiao__c = 'Sul',
            Ativo__c = true
        );
    }

    @IsTest
    static void deveCriarEAtualizarAgendamentoSemDuplicarLead() {
        Id empreendimentoId = obterEmpreendimento().Id;
        PesquisasPortalDTOs.AgendamentoInput primeiro = agendamentoBase(empreendimentoId);

        Test.startTest();
        PesquisasPortalDTOs.OperationResult resultado = PesquisasPortalService.criarAgendamento(primeiro);
        primeiro.bairro = 'Novo Bairro';
        PesquisasPortalService.criarAgendamento(primeiro);
        Test.stopTest();

        Assert.isTrue(resultado.sucesso);
        List<Lead> leads = [
            SELECT Company, CPF_Normalizado__c, Bairro_Desejado__c, Empreendimento__c
            FROM Lead
            WHERE Email = 'pessoa@exemplo.com'
        ];
        Assert.areEqual(1, leads.size());
        Assert.areEqual('Pessoa Física', leads[0].Company);
        Assert.areEqual('Novo Bairro', leads[0].Bairro_Desejado__c);
        Assert.areEqual(empreendimentoId, leads[0].Empreendimento__c);
    }

    @IsTest
    static void deveConsultarERegistrarCheckin() {
        Empreendimento__c empreendimento = obterEmpreendimento();
        insert new Lead(
            LastName = 'Pessoa Existente',
            Company = 'Pessoa Física',
            Email = 'checkin@exemplo.com'
        );
        PesquisasPortalDTOs.IdentificacaoInput input = identificacaoEmail('checkin@exemplo.com', empreendimento.Id);

        Test.startTest();
        PesquisasPortalDTOs.RecepcaoResult consulta = PesquisasPortalService.consultarRecepcao(input);
        PesquisasPortalService.registrarCheckin(input);
        Test.stopTest();

        Assert.areEqual('ENCONTRADO', consulta.status);
        Task checkin = [
            SELECT Status, WhoId, Empreendimento__c, Tipo_Registro_Pesquisas__c
            FROM Task
            WHERE Tipo_Registro_Pesquisas__c = 'Check-in'
            LIMIT 1
        ];
        Assert.areEqual('Completed', checkin.Status);
        Assert.areEqual(empreendimento.Id, checkin.Empreendimento__c);
        Assert.isNotNull(checkin.WhoId);
    }

    @IsTest
    static void deveCriarCadastroRapidoECheckinAtomicamente() {
        PesquisasPortalDTOs.CadastroRapidoInput input = new PesquisasPortalDTOs.CadastroRapidoInput();
        input.nomeCompleto = 'Cadastro Rápido';
        input.telefone = '(11) 98888-7777';
        input.empreendimentoId = obterEmpreendimento().Id;

        Test.startTest();
        PesquisasPortalDTOs.OperationResult resultado = PesquisasPortalService.criarLeadRapidoECheckin(input);
        Test.stopTest();

        Assert.isTrue(resultado.sucesso);
        Assert.areEqual(1, [SELECT COUNT() FROM Lead WHERE Phone = '11988887777']);
        Assert.areEqual(1, [SELECT COUNT() FROM Task WHERE Tipo_Registro_Pesquisas__c = 'Check-in']);
    }

    @IsTest
    static void deveRegistrarAvaliacao() {
        PesquisasPortalDTOs.AvaliacaoInput input = new PesquisasPortalDTOs.AvaliacaoInput();
        input.nomeVendedor = 'Vendedor Teste';
        input.loja = 'Loja Centro';
        input.nota = 5;
        input.observacoes = '<b>Ótimo atendimento</b>';

        Test.startTest();
        PesquisasPortalService.registrarAvaliacao(input);
        Test.stopTest();

        Task avaliacao = [
            SELECT Status, Nota_Avaliacao__c, Estrelas_Avaliacao__c, Description
            FROM Task
            WHERE Tipo_Registro_Pesquisas__c = 'Avaliação'
            LIMIT 1
        ];
        Assert.areEqual('Completed', avaliacao.Status);
        Assert.areEqual(5, avaliacao.Nota_Avaliacao__c);
        Assert.areEqual('★★★★★', avaliacao.Estrelas_Avaliacao__c);
        Assert.areEqual('Ótimo atendimento', avaliacao.Description);
    }

    @IsTest
    static void deveTratarAusenciaEAmbiguidade() {
        Id empreendimentoId = obterEmpreendimento().Id;
        PesquisasPortalDTOs.IdentificacaoInput ausente = identificacaoEmail('ausente@exemplo.com', empreendimentoId);
        insert new List<Lead>{
            new Lead(LastName = 'Duplicado A', Company = 'Teste', Email = 'duplicado@exemplo.com'),
            new Lead(LastName = 'Duplicado B', Company = 'Teste', Email = 'duplicado@exemplo.com')
        };
        PesquisasPortalDTOs.IdentificacaoInput duplicado = identificacaoEmail('duplicado@exemplo.com', empreendimentoId);

        Assert.areEqual('NAO_ENCONTRADO', PesquisasPortalService.consultarRecepcao(ausente).status);
        Assert.areEqual('AMBIGUO', PesquisasPortalService.consultarRecepcao(duplicado).status);
    }

    @IsTest
    static void deveRejeitarAgendamentoEAvaliacaoInvalidos() {
        PesquisasPortalDTOs.AgendamentoInput agendamento = agendamentoBase(obterEmpreendimento().Id);
        agendamento.dataPretendida = Date.today().addDays(-1);
        PesquisasPortalDTOs.AvaliacaoInput avaliacao = new PesquisasPortalDTOs.AvaliacaoInput();
        avaliacao.nota = 0;

        try {
            PesquisasPortalService.criarAgendamento(agendamento);
            Assert.fail('Era esperada uma validação de data.');
        } catch (PesquisasPortalSecurity.PortalException erro) {
            Assert.isTrue(erro.getMessage().contains('data'));
        }
        try {
            PesquisasPortalService.registrarAvaliacao(avaliacao);
            Assert.fail('Era esperada uma validação de nota.');
        } catch (PesquisasPortalSecurity.PortalException erro) {
            Assert.isTrue(erro.getMessage().contains('nota'));
        }
    }

    private static Empreendimento__c obterEmpreendimento() {
        return [SELECT Id FROM Empreendimento__c WHERE Codigo__c = 'TESTE-001' LIMIT 1];
    }

    private static PesquisasPortalDTOs.IdentificacaoInput identificacaoEmail(String email, Id empreendimentoId) {
        PesquisasPortalDTOs.IdentificacaoInput input = new PesquisasPortalDTOs.IdentificacaoInput();
        input.email = email;
        input.empreendimentoId = empreendimentoId;
        return input;
    }

    private static PesquisasPortalDTOs.AgendamentoInput agendamentoBase(Id empreendimentoId) {
        PesquisasPortalDTOs.AgendamentoInput input = new PesquisasPortalDTOs.AgendamentoInput();
        input.nomeCompleto = 'Pessoa Teste';
        input.cpf = '529.982.247-25';
        input.email = 'pessoa@exemplo.com';
        input.telefone = '(11) 99999-9999';
        input.empreendimentoId = empreendimentoId;
        input.dataPretendida = Date.today();
        input.periodo = 'Manhã';
        input.regiao = 'Sul';
        input.bairro = 'Centro';
        return input;
    }
}
