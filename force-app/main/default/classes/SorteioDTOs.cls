public class SorteioDTOs {
    public class CriarSorteioInput {
        @AuraEnabled public String titulo { get; set; }
    }

    public class InscricaoInput {
        @AuraEnabled public String chavePublica { get; set; }
        @AuraEnabled public String nome { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String codigoAcesso { get; set; }
        @AuraEnabled public String honeypot { get; set; }
    }

    public class OperacaoInput {
        @AuraEnabled public String chavePublica { get; set; }
        @AuraEnabled public String tokenOperador { get; set; }
    }

    public class SorteioInfo {
        @AuraEnabled public String titulo { get; set; }
        @AuraEnabled public Boolean inscricoesAbertas { get; set; }
    }

    public class ParticipanteView {
        @AuraEnabled public Integer posicao { get; set; }
        @AuraEnabled public String nome { get; set; }
        @AuraEnabled public String emailMascarado { get; set; }
        @AuraEnabled public Boolean ganhador { get; set; }
        @AuraEnabled public Integer ordem { get; set; }
    }

    public class PainelResult {
        @AuraEnabled public String titulo { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String codigoAcesso { get; set; }
        @AuraEnabled public List<ParticipanteView> participantes { get; set; }
    }

    public class SorteioCriado {
        @AuraEnabled public String chavePublica { get; set; }
        @AuraEnabled public String tokenOperador { get; set; }
        @AuraEnabled public PainelResult painel { get; set; }
    }

    public class SorteioResult {
        @AuraEnabled public ParticipanteView ganhador { get; set; }
        @AuraEnabled public PainelResult painel { get; set; }
    }
}