@IsTest
private class SorteioServiceTest {
    private static SorteioDTOs.SorteioCriado criar(String titulo) {
        SorteioDTOs.CriarSorteioInput input = new SorteioDTOs.CriarSorteioInput();
        input.titulo = titulo;
        return SorteioService.criarSorteio(input);
    }

    private static SorteioDTOs.InscricaoInput inscricao(SorteioDTOs.SorteioCriado sorteio, String email) {
        SorteioDTOs.InscricaoInput input = new SorteioDTOs.InscricaoInput();
        input.chavePublica = sorteio.chavePublica;
        input.nome = 'Participante ' + email;
        input.email = email;
        input.codigoAcesso = sorteio.painel.codigoAcesso;
        return input;
    }

    private static SorteioDTOs.OperacaoInput operador(SorteioDTOs.SorteioCriado sorteio) {
        SorteioDTOs.OperacaoInput input = new SorteioDTOs.OperacaoInput();
        input.chavePublica = sorteio.chavePublica;
        input.tokenOperador = sorteio.tokenOperador;
        return input;
    }

    private static void inserirParticipantes(SorteioDTOs.SorteioCriado sorteio, Integer quantidade) {
        Id sorteioId = [SELECT Id FROM Sorteio__c WHERE Chave_Publica__c = :sorteio.chavePublica].Id;
        List<Participante_Sorteio__c> participantes = new List<Participante_Sorteio__c>();
        for (Integer indice = 0; indice < quantidade; indice++) {
            String email = 'p' + indice + '@teste.com';
            participantes.add(new Participante_Sorteio__c(
                Sorteio__c = sorteioId, Nome__c = 'P' + indice, Email__c = email,
                Chave_Unica__c = sorteioId + '|' + email
            ));
        }
        insert participantes;
    }

    private static void assertInscricaoRejeitada(SorteioDTOs.InscricaoInput input, String mensagem) {
        try {
            SorteioService.inscrever(input);
            Assert.fail('Deveria rejeitar a inscrição');
        } catch (PesquisasPortalSecurity.PortalException erro) {
            Assert.areEqual(mensagem, erro.getMessage());
        }
    }

    private static void assertSorteioRejeitado(SorteioDTOs.OperacaoInput input, String mensagem) {
        try {
            SorteioService.sortear(input);
            Assert.fail('Deveria rejeitar o sorteio');
        } catch (PesquisasPortalSecurity.PortalException erro) {
            Assert.areEqual(mensagem, erro.getMessage());
        }
    }

    @IsTest
    static void criarSorteioGeraDadosDeOperacao() {
        SorteioDTOs.SorteioCriado criado = criar('Festa');
        Sorteio__c registro = [
            SELECT Status__c, Codigo_Acesso__c, Token_Operador_Hash__c, OwnerId
            FROM Sorteio__c WHERE Chave_Publica__c = :criado.chavePublica
        ];
        Assert.areEqual(32, criado.chavePublica.length());
        Assert.isTrue(Pattern.matches('[1-9][0-9]{3}', criado.painel.codigoAcesso));
        Assert.areEqual('Inscricoes_Abertas', registro.Status__c);
        Assert.areEqual(64, registro.Token_Operador_Hash__c.length());
        Assert.areNotEqual(criado.tokenOperador, registro.Token_Operador_Hash__c);
        Assert.areEqual(UserInfo.getUserId(), registro.OwnerId);
        Assert.areEqual('Festa', criado.painel.titulo);
        Assert.isTrue(criado.painel.participantes.isEmpty());
    }

    @IsTest
    static void criarSorteioSemTituloUsaPadrao() {
        Assert.areEqual('Sorteio', criar('   ').painel.titulo);
        Assert.areEqual('Sorteio', SorteioService.criarSorteio(null).painel.titulo);
    }

    @IsTest
    static void consultarSorteioNaoExpoeCodigoNemToken() {
        SorteioDTOs.SorteioCriado criado = criar('Festa');
        SorteioDTOs.SorteioInfo info = SorteioService.consultarSorteio(criado.chavePublica);
        Assert.areEqual('Festa', info.titulo);
        Assert.isTrue(info.inscricoesAbertas);
        Assert.isFalse(JSON.serialize(info).contains(criado.painel.codigoAcesso));
    }

    @IsTest
    static void consultarSorteioInexistenteRejeita() {
        try {
            SorteioService.consultarSorteio('naoexiste');
            Assert.fail('Deveria rejeitar');
        } catch (PesquisasPortalSecurity.PortalException erro) {
            Assert.areEqual('Sorteio não encontrado.', erro.getMessage());
        }
    }

    @IsTest
    static void inscreverValidoNormalizaEmail() {
        SorteioDTOs.SorteioCriado criado = criar('Festa');
        PesquisasPortalDTOs.OperationResult resultado = SorteioService.inscrever(inscricao(criado, '  Ana@Teste.com '));
        Participante_Sorteio__c participante = [SELECT Email__c, Ganhador__c FROM Participante_Sorteio__c];
        Assert.isTrue(resultado.sucesso);
        Assert.areEqual('ana@teste.com', participante.Email__c);
        Assert.isFalse(participante.Ganhador__c);
    }

    @IsTest
    static void inscreverEmailRepetidoRejeita() {
        SorteioDTOs.SorteioCriado criado = criar('Festa');
        SorteioService.inscrever(inscricao(criado, 'ana@teste.com'));
        assertInscricaoRejeitada(inscricao(criado, 'ANA@teste.com'), 'Este e-mail já está cadastrado neste sorteio.');
    }

    @IsTest
    static void mesmoEmailEmSorteiosDiferentesPermitido() {
        SorteioService.inscrever(inscricao(criar('A'), 'ana@teste.com'));
        SorteioService.inscrever(inscricao(criar('B'), 'ana@teste.com'));
        Assert.areEqual(2, [SELECT COUNT() FROM Participante_Sorteio__c]);
    }

    @IsTest
    static void inscreverCodigoInvalidoRejeita() {
        SorteioDTOs.InscricaoInput input = inscricao(criar('Festa'), 'ana@teste.com');
        input.codigoAcesso = '0000';
        assertInscricaoRejeitada(input, 'Código do sorteio inválido.');
    }

    @IsTest
    static void inscreverAposEncerrarRejeita() {
        SorteioDTOs.SorteioCriado criado = criar('Festa');
        SorteioService.encerrarInscricoes(operador(criado));
        assertInscricaoRejeitada(inscricao(criado, 'ana@teste.com'), 'As inscrições deste sorteio estão encerradas.');
    }

    @IsTest
    static void inscreverHoneypotRejeita() {
        SorteioDTOs.InscricaoInput input = inscricao(criar('Festa'), 'ana@teste.com');
        input.honeypot = 'bot';
        assertInscricaoRejeitada(input, 'Não foi possível concluir a inscrição agora.');
    }

    @IsTest
    static void inscreverDadosInvalidosRejeita() {
        SorteioDTOs.SorteioCriado criado = criar('Festa');
        assertInscricaoRejeitada(null, 'Informe os dados da inscrição.');
        assertInscricaoRejeitada(inscricao(criado, 'invalido'), 'Informe um e-mail válido.');
        SorteioDTOs.InscricaoInput semNome = inscricao(criado, 'ana@teste.com');
        semNome.nome = ' ';
        assertInscricaoRejeitada(semNome, 'Informe o nome completo.');
        SorteioDTOs.InscricaoInput chaveErrada = inscricao(criado, 'ana@teste.com');
        chaveErrada.chavePublica = 'naoexiste';
        assertInscricaoRejeitada(chaveErrada, 'Sorteio não encontrado.');
    }

    @IsTest
    static void obterPainelTokenInvalidoRejeita() {
        SorteioDTOs.OperacaoInput input = operador(criar('Festa'));
        input.tokenOperador = 'token-errado';
        try {
            SorteioService.obterPainel(input);
            Assert.fail('Deveria rejeitar');
        } catch (PesquisasPortalSecurity.PortalException erro) {
            Assert.areEqual('Somente quem abriu o sorteio pode controlá-lo.', erro.getMessage());
        }
    }

    @IsTest
    static void obterPainelMascaraEmail() {
        SorteioDTOs.SorteioCriado criado = criar('Festa');
        SorteioService.inscrever(inscricao(criado, 'ana@teste.com'));
        SorteioDTOs.PainelResult painel = SorteioService.obterPainel(operador(criado));
        Assert.areEqual(1, painel.participantes.size());
        Assert.areEqual('a***@teste.com', painel.participantes[0].emailMascarado);
        Assert.areEqual(1, painel.participantes[0].posicao);
    }

    @IsTest
    static void encerrarInscricoesIdempotente() {
        SorteioDTOs.SorteioCriado criado = criar('Festa');
        SorteioService.encerrarInscricoes(operador(criado));
        SorteioDTOs.PainelResult painel = SorteioService.encerrarInscricoes(operador(criado));
        Assert.areEqual('Inscricoes_Encerradas', painel.status);
    }

    @IsTest
    static void sortearComInscricoesAbertasRejeita() {
        SorteioDTOs.SorteioCriado criado = criar('Festa');
        inserirParticipantes(criado, 2);
        assertSorteioRejeitado(operador(criado), 'Encerre as inscrições antes de sortear.');
    }

    @IsTest
    static void sortearSemParticipantesRejeita() {
        SorteioDTOs.SorteioCriado criado = criar('Festa');
        SorteioService.encerrarInscricoes(operador(criado));
        assertSorteioRejeitado(operador(criado), 'Não há participantes restantes para sortear.');
    }

    @IsTest
    static void sortearVariasRodadasNaoRepeteGanhador() {
        SorteioDTOs.SorteioCriado criado = criar('Festa');
        inserirParticipantes(criado, 200);
        SorteioService.encerrarInscricoes(operador(criado));
        Set<String> ganhadores = new Set<String>();
        Test.startTest();
        for (Integer rodada = 1; rodada <= 5; rodada++) {
            SorteioDTOs.SorteioResult resultado = SorteioService.sortear(operador(criado));
            Assert.areEqual(rodada, resultado.ganhador.ordem);
            ganhadores.add(resultado.ganhador.emailMascarado + resultado.ganhador.nome);
        }
        Test.stopTest();
        Assert.areEqual(5, ganhadores.size());
        Assert.areEqual(5, [SELECT COUNT() FROM Participante_Sorteio__c WHERE Ganhador__c = TRUE]);
    }

    @IsTest
    static void sortearTodosRejeitaProximo() {
        SorteioDTOs.SorteioCriado criado = criar('Festa');
        inserirParticipantes(criado, 2);
        SorteioService.encerrarInscricoes(operador(criado));
        SorteioService.sortear(operador(criado));
        SorteioDTOs.SorteioResult ultimo = SorteioService.sortear(operador(criado));
        Assert.areEqual(2, ultimo.painel.participantes.size());
        assertSorteioRejeitado(operador(criado), 'Não há participantes restantes para sortear.');
    }

    @IsTest
    static void finalizarBloqueiaNovoSorteio() {
        SorteioDTOs.SorteioCriado criado = criar('Festa');
        inserirParticipantes(criado, 2);
        SorteioService.encerrarInscricoes(operador(criado));
        Assert.areEqual('Finalizado', SorteioService.finalizar(operador(criado)).status);
        assertSorteioRejeitado(operador(criado), 'Este sorteio já foi finalizado.');
    }

    @IsTest
    static void indiceAleatorioSempreDentroDoIntervalo() {
        for (Integer tentativa = 0; tentativa < 500; tentativa++) {
            Integer indice = SorteioService.indiceAleatorio(7);
            Assert.isTrue(indice >= 0 && indice < 7, 'Índice fora do intervalo: ' + indice);
        }
    }
}