@IsTest
private class SorteioControllerTest {
    private static SorteioDTOs.OperacaoInput operador(SorteioDTOs.SorteioCriado criado) {
        SorteioDTOs.OperacaoInput input = new SorteioDTOs.OperacaoInput();
        input.chavePublica = criado.chavePublica;
        input.tokenOperador = criado.tokenOperador;
        return input;
    }

    @IsTest
    static void fluxoCompletoPeloController() {
        SorteioDTOs.SorteioCriado criado = SorteioController.criarSorteio(new SorteioDTOs.CriarSorteioInput());
        Assert.isTrue(SorteioController.consultarSorteio(criado.chavePublica).inscricoesAbertas);

        SorteioDTOs.InscricaoInput inscricao = new SorteioDTOs.InscricaoInput();
        inscricao.chavePublica = criado.chavePublica;
        inscricao.nome = 'Ana';
        inscricao.email = 'ana@teste.com';
        inscricao.codigoAcesso = criado.painel.codigoAcesso;
        Assert.isTrue(SorteioController.inscrever(inscricao).sucesso);

        Assert.areEqual(1, SorteioController.obterPainel(operador(criado)).participantes.size());
        Assert.areEqual('Inscricoes_Encerradas', SorteioController.encerrarInscricoes(operador(criado)).status);
        Assert.areEqual('Ana', SorteioController.sortear(operador(criado)).ganhador.nome);
        Assert.areEqual('Finalizado', SorteioController.finalizar(operador(criado)).status);
    }

    @IsTest
    static void erroDeRegraChegaAoUsuario() {
        try {
            SorteioController.consultarSorteio('naoexiste');
            Assert.fail('Deveria lançar AuraHandledException');
        } catch (AuraHandledException erro) {
            Assert.areEqual('Sorteio não encontrado.', erro.getMessage());
        }
    }

    @IsTest
    static void operacoesDeOperadorSemTokenRejeitam() {
        SorteioDTOs.OperacaoInput semToken = new SorteioDTOs.OperacaoInput();
        for (Integer metodo = 0; metodo < 4; metodo++) {
            try {
                if (metodo == 0) { SorteioController.obterPainel(semToken); }
                if (metodo == 1) { SorteioController.encerrarInscricoes(semToken); }
                if (metodo == 2) { SorteioController.sortear(semToken); }
                if (metodo == 3) { SorteioController.finalizar(semToken); }
                Assert.fail('Deveria rejeitar');
            } catch (AuraHandledException erro) {
                Assert.areEqual('Somente quem abriu o sorteio pode controlá-lo.', erro.getMessage());
            }
        }
    }
}