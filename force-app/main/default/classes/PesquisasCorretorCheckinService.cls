public inherited sharing class PesquisasCorretorCheckinService {
  private static final String MENSAGEM_SUCESSO = 'Check-in confirmado com sucesso.';
  private static final String MENSAGEM_CONFIGURACAO = 'Não foi possível carregar a loja padrão.';

  public static PesquisasPortalDTOs.LojaOption obterLojaPadrao() {
    List<Loja__c> lojas = [
      SELECT Codigo__c, Name, Endereco__c, Loja_Padrao__c
      FROM Loja__c
      WHERE Ativa__c = TRUE AND Loja_Padrao__c = TRUE
      ORDER BY Ordem_Exibicao__c ASC NULLS LAST, Name ASC
      LIMIT 2
    ];
    if (lojas.size() != 1) {
      throw new PesquisasPortalSecurity.PortalException(MENSAGEM_CONFIGURACAO);
    }
    return criarOpcao(lojas[0]);
  }

  public static List<PesquisasPortalDTOs.LojaOption> listarLojasAtivas() {
    List<PesquisasPortalDTOs.LojaOption> resultado = new List<PesquisasPortalDTOs.LojaOption>();
    for (Loja__c loja : [
      SELECT Codigo__c, Name, Endereco__c, Loja_Padrao__c
      FROM Loja__c
      WHERE Ativa__c = TRUE
      ORDER BY Ordem_Exibicao__c ASC NULLS LAST, Name ASC
      LIMIT 500
    ]) {
      resultado.add(criarOpcao(loja));
    }
    return resultado;
  }

  public static PesquisasPortalDTOs.OperationResult confirmarCheckin(
    PesquisasPortalDTOs.CheckinCorretorInput input
  ) {
    validarPayload(input);
    String cpf = PesquisasPortalSecurity.normalizarCpfObrigatorio(input.cpf);
    Loja__c loja = obterLojaAtiva(input.codigoLoja);
    Checkin_Corretor__c registro = new Checkin_Corretor__c(
      CPF_Normalizado__c = cpf,
      Loja__c = loja.Id,
      Data_Hora_Checkin__c = System.now()
    );
    insert as user registro;
    return new PesquisasPortalDTOs.OperationResult(true, MENSAGEM_SUCESSO);
  }

  private static void validarPayload(
    PesquisasPortalDTOs.CheckinCorretorInput input
  ) {
    if (input == null) {
      throw new PesquisasPortalSecurity.PortalException(
        'Informe os dados do check-in.'
      );
    }
    if (String.isNotBlank(input.honeypot)) {
      throw new PesquisasPortalSecurity.PortalException(
        'Não foi possível confirmar o check-in agora.'
      );
    }
  }

  private static Loja__c obterLojaAtiva(String codigoInformado) {
    String codigo = PesquisasPortalSecurity.textoSeguro(codigoInformado, 80);
    if (String.isBlank(codigo)) {
      throw new PesquisasPortalSecurity.PortalException(
        'Selecione uma loja válida.'
      );
    }
    List<Loja__c> lojas = [
      SELECT Id
      FROM Loja__c
      WHERE Codigo__c = :codigo AND Ativa__c = TRUE
      LIMIT 1
    ];
    if (lojas.isEmpty()) {
      throw new PesquisasPortalSecurity.PortalException(
        'Selecione uma loja válida.'
      );
    }
    return lojas[0];
  }

  private static PesquisasPortalDTOs.LojaOption criarOpcao(Loja__c loja) {
    PesquisasPortalDTOs.LojaOption opcao = new PesquisasPortalDTOs.LojaOption();
    opcao.codigo = loja.Codigo__c;
    opcao.nome = loja.Name;
    opcao.endereco = loja.Endereco__c;
    opcao.padrao = loja.Loja_Padrao__c;
    return opcao;
  }
}
