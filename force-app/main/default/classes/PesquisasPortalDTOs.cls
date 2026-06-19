public class PesquisasPortalDTOs {
    public class LojaOption {
        @AuraEnabled public String codigo { get; set; }
        @AuraEnabled public String nome { get; set; }
        @AuraEnabled public String endereco { get; set; }
        @AuraEnabled public Boolean padrao { get; set; }
    }

    public class CheckinCorretorInput {
        @AuraEnabled public String cpf { get; set; }
        @AuraEnabled public String codigoLoja { get; set; }
        @AuraEnabled public String honeypot { get; set; }
    }

    public class EmpreendimentoOption {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String nome { get; set; }
        @AuraEnabled public String bairro { get; set; }
        @AuraEnabled public String regiao { get; set; }
    }

    public virtual class IdentificacaoInput {
        @AuraEnabled public String cpf { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String telefone { get; set; }
        @AuraEnabled public Id empreendimentoId { get; set; }
    }

    public class AgendamentoInput extends IdentificacaoInput {
        @AuraEnabled public String nomeCompleto { get; set; }
        @AuraEnabled public String regiao { get; set; }
        @AuraEnabled public String bairro { get; set; }
        @AuraEnabled public Date dataPretendida { get; set; }
        @AuraEnabled public String periodo { get; set; }
        @AuraEnabled public String observacoes { get; set; }
    }

    public class CadastroRapidoInput extends IdentificacaoInput {
        @AuraEnabled public String nomeCompleto { get; set; }
    }

    public class AvaliacaoInput {
        @AuraEnabled public String nomeVendedor { get; set; }
        @AuraEnabled public String loja { get; set; }
        @AuraEnabled public Integer nota { get; set; }
        @AuraEnabled public String observacoes { get; set; }
    }

    public class OperationResult {
        @AuraEnabled public Boolean sucesso { get; set; }
        @AuraEnabled public String mensagem { get; set; }

        public OperationResult(Boolean sucesso, String mensagem) {
            this.sucesso = sucesso;
            this.mensagem = mensagem;
        }
    }

    public class RecepcaoResult {
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String mensagem { get; set; }

        public RecepcaoResult(String status, String mensagem) {
            this.status = status;
            this.mensagem = mensagem;
        }
    }
}
