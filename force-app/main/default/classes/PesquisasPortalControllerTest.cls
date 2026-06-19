@IsTest
private class PesquisasPortalControllerTest {
    @TestSetup
    static void criarDados() {
        insert new Empreendimento__c(
            Name = 'Empreendimento Controller',
            Codigo__c = 'CTRL-001',
            Ativo__c = true
        );
    }

    @IsTest
    static void deveExporEmpreendimentosEAgendamento() {
        Id empreendimentoId = [SELECT Id FROM Empreendimento__c WHERE Codigo__c = 'CTRL-001'].Id;
        PesquisasPortalDTOs.AgendamentoInput input = new PesquisasPortalDTOs.AgendamentoInput();
        input.nomeCompleto = 'Pessoa Controller';
        input.email = 'controller@exemplo.com';
        input.empreendimentoId = empreendimentoId;
        input.dataPretendida = Date.today();
        input.periodo = 'Tarde';

        Test.startTest();
        List<PesquisasPortalDTOs.EmpreendimentoOption> opcoes =
            PesquisasPortalController.listarEmpreendimentos();
        PesquisasPortalDTOs.OperationResult resultado =
            PesquisasPortalController.criarAgendamento(input);
        Test.stopTest();

        Assert.areEqual(1, opcoes.size());
        Assert.isTrue(resultado.sucesso);
    }

    @IsTest
    static void deveConverterErroFuncional() {
        try {
            PesquisasPortalController.consultarRecepcao(new PesquisasPortalDTOs.IdentificacaoInput());
            Assert.fail('Era esperado um AuraHandledException.');
        } catch (AuraHandledException erro) {
            Assert.isTrue(erro.getMessage().contains('CPF'));
        }
    }

    @IsTest
    static void deveExporRecepcaoCheckinCadastroRapidoEAvaliacao() {
        Id empreendimentoId = [SELECT Id FROM Empreendimento__c WHERE Codigo__c = 'CTRL-001'].Id;
        insert new Lead(LastName = 'Recepção', Company = 'Teste', Email = 'recepcao@exemplo.com');
        PesquisasPortalDTOs.IdentificacaoInput recepcao = new PesquisasPortalDTOs.IdentificacaoInput();
        recepcao.email = 'recepcao@exemplo.com';
        recepcao.empreendimentoId = empreendimentoId;
        PesquisasPortalDTOs.CadastroRapidoInput rapido = new PesquisasPortalDTOs.CadastroRapidoInput();
        rapido.nomeCompleto = 'Pessoa Rápida';
        rapido.telefone = '11977776666';
        rapido.empreendimentoId = empreendimentoId;
        PesquisasPortalDTOs.AvaliacaoInput avaliacao = new PesquisasPortalDTOs.AvaliacaoInput();
        avaliacao.nomeVendedor = 'Vendedor';
        avaliacao.loja = 'Loja';
        avaliacao.nota = 4;

        Test.startTest();
        PesquisasPortalDTOs.RecepcaoResult consulta = PesquisasPortalController.consultarRecepcao(recepcao);
        PesquisasPortalController.registrarCheckin(recepcao);
        PesquisasPortalController.criarLeadRapidoECheckin(rapido);
        PesquisasPortalController.registrarAvaliacao(avaliacao);
        Test.stopTest();

        Assert.areEqual('ENCONTRADO', consulta.status);
        Assert.areEqual(3, [SELECT COUNT() FROM Task]);
    }

    @IsTest
    static void deveTratarErrosNasOperacoesPublicas() {
        PesquisasPortalDTOs.AvaliacaoInput avaliacao = new PesquisasPortalDTOs.AvaliacaoInput();
        avaliacao.nota = 0;
        try {
            PesquisasPortalController.registrarAvaliacao(avaliacao);
            Assert.fail('Era esperado erro de avaliação.');
        } catch (AuraHandledException erro) {
            Assert.isTrue(erro.getMessage().contains('nota'));
        }

        PesquisasPortalDTOs.CadastroRapidoInput rapido = new PesquisasPortalDTOs.CadastroRapidoInput();
        try {
            PesquisasPortalController.criarLeadRapidoECheckin(rapido);
            Assert.fail('Era esperado erro de cadastro.');
        } catch (AuraHandledException erro) {
            Assert.isTrue(erro.getMessage().contains('nome'));
        }
    }
}
