public with sharing class SorteioController {
    @AuraEnabled
    public static SorteioDTOs.SorteioCriado criarSorteio(SorteioDTOs.CriarSorteioInput input) {
        try {
            return SorteioService.criarSorteio(input);
        } catch (Exception erro) {
            throw converterErro(erro);
        }
    }

    @AuraEnabled
    public static SorteioDTOs.SorteioInfo consultarSorteio(String chavePublica) {
        try {
            return SorteioService.consultarSorteio(chavePublica);
        } catch (Exception erro) {
            throw converterErro(erro);
        }
    }

    @AuraEnabled
    public static PesquisasPortalDTOs.OperationResult inscrever(SorteioDTOs.InscricaoInput input) {
        try {
            return SorteioService.inscrever(input);
        } catch (Exception erro) {
            throw converterErro(erro);
        }
    }

    @AuraEnabled
    public static SorteioDTOs.PainelResult obterPainel(SorteioDTOs.OperacaoInput input) {
        try {
            return SorteioService.obterPainel(input);
        } catch (Exception erro) {
            throw converterErro(erro);
        }
    }

    @AuraEnabled
    public static SorteioDTOs.PainelResult encerrarInscricoes(SorteioDTOs.OperacaoInput input) {
        try {
            return SorteioService.encerrarInscricoes(input);
        } catch (Exception erro) {
            throw converterErro(erro);
        }
    }

    @AuraEnabled
    public static SorteioDTOs.SorteioResult sortear(SorteioDTOs.OperacaoInput input) {
        try {
            return SorteioService.sortear(input);
        } catch (Exception erro) {
            throw converterErro(erro);
        }
    }

    @AuraEnabled
    public static SorteioDTOs.PainelResult finalizar(SorteioDTOs.OperacaoInput input) {
        try {
            return SorteioService.finalizar(input);
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