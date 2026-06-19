@IsTest
private class PesquisasPortalSecurityTest {
    @IsTest
    static void deveNormalizarEValidarIdentificacao() {
        PesquisasPortalDTOs.IdentificacaoInput input = new PesquisasPortalDTOs.IdentificacaoInput();
        input.cpf = '529.982.247-25';
        input.email = ' PESSOA@EXEMPLO.COM ';
        input.telefone = '(11) 99999-9999';

        PesquisasPortalSecurity.IdentificacaoNormalizada resultado =
            PesquisasPortalSecurity.normalizarIdentificacao(input);

        Assert.areEqual('52998224725', resultado.cpf);
        Assert.areEqual('pessoa@exemplo.com', resultado.email);
        Assert.areEqual('11999999999', resultado.telefone);
        Assert.isTrue(PesquisasPortalSecurity.cpfValido(resultado.cpf));
    }

    @IsTest
    static void deveRejeitarIdentificacaoInvalida() {
        PesquisasPortalDTOs.IdentificacaoInput input = new PesquisasPortalDTOs.IdentificacaoInput();
        input.cpf = '111.111.111-11';

        try {
            PesquisasPortalSecurity.normalizarIdentificacao(input);
            Assert.fail('Era esperada uma validação de CPF.');
        } catch (PesquisasPortalSecurity.PortalException erro) {
            Assert.areEqual('Informe um CPF válido.', erro.getMessage());
        }
    }

    @IsTest
    static void deveSanitizarTexto() {
        Assert.areEqual('Texto', PesquisasPortalSecurity.textoSeguro('<script>alert(1)</script>Texto', 100));
        Assert.areEqual('12345678909', PesquisasPortalSecurity.normalizarDigitos('123.456.789-09'));
    }
}
