public with sharing class PesquisasPortalController {
    @AuraEnabled(cacheable=true)
    public static PesquisasPortalDTOs.LojaOption obterLojaPadrao() {
        try {
            return PesquisasCorretorCheckinService.obterLojaPadrao();
        } catch (Exception erro) {
            throw converterErro(erro);
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<PesquisasPortalDTOs.LojaOption> listarLojasAtivas() {
        try {
            return PesquisasCorretorCheckinService.listarLojasAtivas();
        } catch (Exception erro) {
            throw converterErro(erro);
        }
    }

    @AuraEnabled
    public static PesquisasPortalDTOs.OperationResult confirmarCheckinCorretor(
        PesquisasPortalDTOs.CheckinCorretorInput input
    ) {
        try {
            return PesquisasCorretorCheckinService.confirmarCheckin(input);
        } catch (Exception erro) {
            throw converterErro(erro);
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<PesquisasPortalDTOs.EmpreendimentoOption> listarEmpreendimentos() {
        try {
            return PesquisasPortalService.listarEmpreendimentos();
        } catch (Exception erro) {
            throw converterErro(erro);
        }
    }

    @AuraEnabled
    public static PesquisasPortalDTOs.OperationResult criarAgendamento(
        PesquisasPortalDTOs.AgendamentoInput input
    ) {
        try {
            return PesquisasPortalService.criarAgendamento(input);
        } catch (Exception erro) {
            throw converterErro(erro);
        }
    }

    @AuraEnabled
    public static PesquisasPortalDTOs.RecepcaoResult consultarRecepcao(
        PesquisasPortalDTOs.IdentificacaoInput input
    ) {
        try {
            return PesquisasPortalService.consultarRecepcao(input);
        } catch (Exception erro) {
            throw converterErro(erro);
        }
    }

    @AuraEnabled
    public static PesquisasPortalDTOs.OperationResult registrarCheckin(
        PesquisasPortalDTOs.IdentificacaoInput input
    ) {
        try {
            return PesquisasPortalService.registrarCheckin(input);
        } catch (Exception erro) {
            throw converterErro(erro);
        }
    }

    @AuraEnabled
    public static PesquisasPortalDTOs.OperationResult criarLeadRapidoECheckin(
        PesquisasPortalDTOs.CadastroRapidoInput input
    ) {
        try {
            return PesquisasPortalService.criarLeadRapidoECheckin(input);
        } catch (Exception erro) {
            throw converterErro(erro);
        }
    }

    @AuraEnabled
    public static PesquisasPortalDTOs.OperationResult registrarAvaliacao(
        PesquisasPortalDTOs.AvaliacaoInput input
    ) {
        try {
            return PesquisasPortalService.registrarAvaliacao(input);
        } catch (Exception erro) {
            throw converterErro(erro);
        }
    }

    private static AuraHandledException converterErro(Exception erro) {
        String mensagem = erro instanceof PesquisasPortalSecurity.PortalException
            ? erro.getMessage()
            : 'Não foi possível concluir a solicitação. Tente novamente.';
        AuraHandledException tratado = new AuraHandledException(mensagem);
        tratado.setMessage(mensagem);
        return tratado;
    }
}
