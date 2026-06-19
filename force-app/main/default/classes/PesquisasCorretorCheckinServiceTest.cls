@IsTest
private class PesquisasCorretorCheckinServiceTest {
  @TestSetup
  static void criarDados() {
    atribuirPermissaoAoUsuarioDeTeste();
    insert new List<Loja__c>{
      new Loja__c(
        Name = 'Loja Morumbi',
        Codigo__c = 'LOJA-MORUMBI',
        Endereco__c = 'Av. Giovanni Gronchi, 2967',
        Ativa__c = true,
        Loja_Padrao__c = true,
        Ordem_Exibicao__c = 1
      ),
      new Loja__c(
        Name = 'Loja Tatuapé',
        Codigo__c = 'LOJA-TATUAPE',
        Endereco__c = 'Rua Tuiuti, 2147',
        Ativa__c = true,
        Loja_Padrao__c = false,
        Ordem_Exibicao__c = 2
      ),
      new Loja__c(
        Name = 'Loja Inativa',
        Codigo__c = 'LOJA-INATIVA',
        Endereco__c = 'Endereço inativo',
        Ativa__c = false,
        Loja_Padrao__c = false,
        Ordem_Exibicao__c = 3
      )
    };
  }

  @IsTest
  static void deveObterPadraoEListarSomenteAtivas() {
    Test.startTest();
    PesquisasPortalDTOs.LojaOption padrao = PesquisasCorretorCheckinService.obterLojaPadrao();
    List<PesquisasPortalDTOs.LojaOption> lojas = PesquisasCorretorCheckinService.listarLojasAtivas();
    Test.stopTest();

    Assert.areEqual('LOJA-MORUMBI', padrao.codigo);
    Assert.isTrue(padrao.padrao);
    Assert.areEqual(2, lojas.size());
    Assert.areEqual('LOJA-MORUMBI', lojas[0].codigo);
    Assert.areEqual('LOJA-TATUAPE', lojas[1].codigo);
  }

  @IsTest
  static void deveConfirmarCheckinComCpfNormalizado() {
    PesquisasPortalDTOs.CheckinCorretorInput input = entradaValida();

    Test.startTest();
    PesquisasPortalDTOs.OperationResult resultado = PesquisasCorretorCheckinService.confirmarCheckin(
      input
    );
    Test.stopTest();

    Checkin_Corretor__c registro = [
      SELECT CPF_Normalizado__c, Loja__r.Codigo__c, Data_Hora_Checkin__c
      FROM Checkin_Corretor__c
      LIMIT 1
    ];
    Assert.isTrue(resultado.sucesso);
    Assert.areEqual('Check-in confirmado com sucesso.', resultado.mensagem);
    Assert.areEqual('52998224725', registro.CPF_Normalizado__c);
    Assert.areEqual('LOJA-MORUMBI', registro.Loja__r.Codigo__c);
    Assert.isNotNull(registro.Data_Hora_Checkin__c);
  }

  @IsTest
  static void deveRejeitarCpfLojaEHoneypotInvalidos() {
    validarErro(entrada('111.111.111-11', 'LOJA-MORUMBI', null), 'CPF válido');
    validarErro(entrada('529.982.247-25', 'LOJA-INATIVA', null), 'loja válida');
    validarErro(
      entrada('529.982.247-25', 'CODIGO-INEXISTENTE', null),
      'loja válida'
    );
    validarErro(
      entrada('529.982.247-25', 'LOJA-MORUMBI', 'robô'),
      'confirmar o check-in'
    );
    Assert.areEqual(0, [SELECT COUNT() FROM Checkin_Corretor__c]);
  }

  @IsTest
  static void deveRejeitarConfiguracaoPadraoAusenteOuDuplicada() {
    Loja__c morumbi = [
      SELECT Id, Loja_Padrao__c
      FROM Loja__c
      WHERE Codigo__c = 'LOJA-MORUMBI'
    ];
    morumbi.Loja_Padrao__c = false;
    update morumbi;
    validarErroLojaPadrao();

    List<Loja__c> ativas = [
      SELECT Id, Loja_Padrao__c
      FROM Loja__c
      WHERE Ativa__c = TRUE
    ];
    for (Loja__c loja : ativas) {
      loja.Loja_Padrao__c = true;
    }

    update ativas;
    validarErroLojaPadrao();
  }

  private static void atribuirPermissaoAoUsuarioDeTeste() {
    PermissionSet permissao = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'Pesquisas_Checkin_Corretor_Acesso'
      LIMIT 1
    ];
    if (
      [
        SELECT COUNT()
        FROM PermissionSetAssignment
        WHERE
          AssigneeId = :UserInfo.getUserId()
          AND PermissionSetId = :permissao.Id
      ] > 0
    ) {
      return;
    }
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert new PermissionSetAssignment(
        AssigneeId = UserInfo.getUserId(),
        PermissionSetId = permissao.Id
      );
    }
  }

  private static PesquisasPortalDTOs.CheckinCorretorInput entradaValida() {
    return entrada('529.982.247-25', 'LOJA-MORUMBI', null);
  }

  private static PesquisasPortalDTOs.CheckinCorretorInput entrada(
    String cpf,
    String codigo,
    String honeypot
  ) {
    PesquisasPortalDTOs.CheckinCorretorInput input = new PesquisasPortalDTOs.CheckinCorretorInput();
    input.cpf = cpf;
    input.codigoLoja = codigo;
    input.honeypot = honeypot;
    return input;
  }

  private static void validarErro(
    PesquisasPortalDTOs.CheckinCorretorInput input,
    String trechoEsperado
  ) {
    try {
      PesquisasCorretorCheckinService.confirmarCheckin(input);
      Assert.fail('Era esperado um erro funcional.');
    } catch (PesquisasPortalSecurity.PortalException erro) {
      Assert.isTrue(erro.getMessage().contains(trechoEsperado));
    }
  }

  private static void validarErroLojaPadrao() {
    try {
      PesquisasCorretorCheckinService.obterLojaPadrao();
      Assert.fail('Era esperado erro de configuração da loja padrão.');
    } catch (PesquisasPortalSecurity.PortalException erro) {
      Assert.isTrue(erro.getMessage().contains('loja padrão'));
    }
  }
}
