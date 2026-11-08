public without sharing class SorteioService {
    private static final String STATUS_ABERTO = 'Inscricoes_Abertas';
    private static final String STATUS_ENCERRADO = 'Inscricoes_Encerradas';
    private static final String STATUS_FINALIZADO = 'Finalizado';
    private static final String TITULO_PADRAO = 'Sorteio';
    private static final Integer LIMITE_PARTICIPANTES = 2000;
    private static final String MENSAGEM_INSCRITO = 'Inscrição confirmada! Boa sorte e acompanhe o telão.';
    private static final String MENSAGEM_DUPLICADO = 'Este e-mail já está cadastrado neste sorteio.';
    private static final String MENSAGEM_NAO_ENCONTRADO = 'Sorteio não encontrado.';
    private static final String MENSAGEM_SEM_PERMISSAO = 'Somente quem abriu o sorteio pode controlá-lo.';
    private static final String MENSAGEM_SEM_RESTANTES = 'Não há participantes restantes para sortear.';

    public static SorteioDTOs.SorteioCriado criarSorteio(SorteioDTOs.CriarSorteioInput input) {
        String token = gerarChaveAleatoria();
        Sorteio__c sorteio = new Sorteio__c(
            Titulo__c = tituloOuPadrao(input),
            Status__c = STATUS_ABERTO,
            Codigo_Acesso__c = String.valueOf(1000 + indiceAleatorio(9000)),
            Chave_Publica__c = gerarChaveAleatoria(),
            Token_Operador_Hash__c = gerarHash(token),
            OwnerId = resolverProprietario()
        );
        insert sorteio;
        SorteioDTOs.SorteioCriado resultado = new SorteioDTOs.SorteioCriado();
        resultado.chavePublica = sorteio.Chave_Publica__c;
        resultado.tokenOperador = token;
        resultado.painel = montarPainel(sorteio);
        return resultado;
    }

    public static SorteioDTOs.SorteioInfo consultarSorteio(String chavePublica) {
        Sorteio__c sorteio = buscarSorteio(chavePublica, false);
        SorteioDTOs.SorteioInfo info = new SorteioDTOs.SorteioInfo();
        info.titulo = sorteio.Titulo__c;
        info.inscricoesAbertas = sorteio.Status__c == STATUS_ABERTO;
        return info;
    }

    public static PesquisasPortalDTOs.OperationResult inscrever(SorteioDTOs.InscricaoInput input) {
        validarInscricao(input);
        String nome = PesquisasPortalSecurity.nomeObrigatorio(input.nome);
        String email = PesquisasPortalSecurity.emailObrigatorio(input.email);
        Sorteio__c sorteio = buscarSorteio(input.chavePublica, true);
        validarAbertoECodigo(sorteio, input.codigoAcesso);
        inserirParticipante(new Participante_Sorteio__c(
            Sorteio__c = sorteio.Id,
            Nome__c = nome,
            Email__c = email,
            Chave_Unica__c = sorteio.Id + '|' + email
        ));
        return new PesquisasPortalDTOs.OperationResult(true, MENSAGEM_INSCRITO);
    }

    public static SorteioDTOs.PainelResult obterPainel(SorteioDTOs.OperacaoInput input) {
        return montarPainel(buscarComoOperador(input, false));
    }

    public static SorteioDTOs.PainelResult encerrarInscricoes(SorteioDTOs.OperacaoInput input) {
        Sorteio__c sorteio = buscarComoOperador(input, true);
        if (sorteio.Status__c == STATUS_ABERTO) {
            sorteio.Status__c = STATUS_ENCERRADO;
            sorteio.Data_Encerramento_Inscricoes__c = System.now();
            update sorteio;
        }
        return montarPainel(sorteio);
    }

    public static SorteioDTOs.SorteioResult sortear(SorteioDTOs.OperacaoInput input) {
        Sorteio__c sorteio = buscarComoOperador(input, true);
        validarPodeSortear(sorteio);
        List<Participante_Sorteio__c> restantes = [
            SELECT Id, Nome__c, Email__c, Ganhador__c, Ordem_Sorteio__c
            FROM Participante_Sorteio__c
            WHERE Sorteio__c = :sorteio.Id AND Ganhador__c = FALSE
            ORDER BY CreatedDate, Id
            LIMIT :LIMITE_PARTICIPANTES
        ];
        if (restantes.isEmpty()) {
            throw new PesquisasPortalSecurity.PortalException(MENSAGEM_SEM_RESTANTES);
        }
        Participante_Sorteio__c ganhador = restantes[indiceAleatorio(restantes.size())];
        ganhador.Ganhador__c = true;
        ganhador.Ordem_Sorteio__c = proximaOrdem(sorteio.Id);
        ganhador.Data_Sorteio__c = System.now();
        update ganhador;
        SorteioDTOs.SorteioResult resultado = new SorteioDTOs.SorteioResult();
        resultado.ganhador = criarView(ganhador, null);
        resultado.painel = montarPainel(sorteio);
        return resultado;
    }

    public static SorteioDTOs.PainelResult finalizar(SorteioDTOs.OperacaoInput input) {
        Sorteio__c sorteio = buscarComoOperador(input, true);
        if (sorteio.Status__c != STATUS_FINALIZADO) {
            sorteio.Status__c = STATUS_FINALIZADO;
            update sorteio;
        }
        return montarPainel(sorteio);
    }

    @TestVisible
    private static Integer indiceAleatorio(Integer total) {
        Integer indice = Math.mod(Crypto.getRandomInteger(), total);
        return indice < 0 ? indice + total : indice;
    }

    private static void validarInscricao(SorteioDTOs.InscricaoInput input) {
        if (input == null) {
            throw new PesquisasPortalSecurity.PortalException('Informe os dados da inscrição.');
        }
        if (String.isNotBlank(input.honeypot)) {
            throw new PesquisasPortalSecurity.PortalException('Não foi possível concluir a inscrição agora.');
        }
    }

    private static void validarAbertoECodigo(Sorteio__c sorteio, String codigoInformado) {
        if (sorteio.Status__c != STATUS_ABERTO) {
            throw new PesquisasPortalSecurity.PortalException('As inscrições deste sorteio estão encerradas.');
        }
        String codigo = PesquisasPortalSecurity.textoSeguro(codigoInformado, 10);
        if (codigo == null || !codigo.equals(sorteio.Codigo_Acesso__c)) {
            throw new PesquisasPortalSecurity.PortalException('Código do sorteio inválido.');
        }
    }

    private static void validarPodeSortear(Sorteio__c sorteio) {
        if (sorteio.Status__c == STATUS_ABERTO) {
            throw new PesquisasPortalSecurity.PortalException('Encerre as inscrições antes de sortear.');
        }
        if (sorteio.Status__c == STATUS_FINALIZADO) {
            throw new PesquisasPortalSecurity.PortalException('Este sorteio já foi finalizado.');
        }
    }

    private static void inserirParticipante(Participante_Sorteio__c participante) {
        try {
            insert participante;
        } catch (DmlException erro) {
            if (erro.getDmlType(0) == StatusCode.DUPLICATE_VALUE) {
                throw new PesquisasPortalSecurity.PortalException(MENSAGEM_DUPLICADO);
            }
            throw erro;
        }
    }

    private static Sorteio__c buscarComoOperador(SorteioDTOs.OperacaoInput input, Boolean bloquear) {
        if (input == null || String.isBlank(input.tokenOperador)) {
            throw new PesquisasPortalSecurity.PortalException(MENSAGEM_SEM_PERMISSAO);
        }
        Sorteio__c sorteio = buscarSorteio(input.chavePublica, bloquear);
        if (!gerarHash(input.tokenOperador).equals(sorteio.Token_Operador_Hash__c)) {
            throw new PesquisasPortalSecurity.PortalException(MENSAGEM_SEM_PERMISSAO);
        }
        return sorteio;
    }

    private static Sorteio__c buscarSorteio(String chavePublica, Boolean bloquear) {
        String chave = PesquisasPortalSecurity.textoSeguro(chavePublica, 32);
        if (String.isBlank(chave)) {
            throw new PesquisasPortalSecurity.PortalException(MENSAGEM_NAO_ENCONTRADO);
        }
        List<Sorteio__c> sorteios = bloquear
            ? [SELECT Id, Titulo__c, Status__c, Codigo_Acesso__c, Token_Operador_Hash__c
               FROM Sorteio__c WHERE Chave_Publica__c = :chave LIMIT 1 FOR UPDATE]
            : [SELECT Id, Titulo__c, Status__c, Codigo_Acesso__c, Token_Operador_Hash__c
               FROM Sorteio__c WHERE Chave_Publica__c = :chave LIMIT 1];
        if (sorteios.isEmpty()) {
            throw new PesquisasPortalSecurity.PortalException(MENSAGEM_NAO_ENCONTRADO);
        }
        return sorteios[0];
    }

    private static SorteioDTOs.PainelResult montarPainel(Sorteio__c sorteio) {
        SorteioDTOs.PainelResult painel = new SorteioDTOs.PainelResult();
        painel.titulo = sorteio.Titulo__c;
        painel.status = sorteio.Status__c;
        painel.codigoAcesso = sorteio.Codigo_Acesso__c;
        painel.participantes = new List<SorteioDTOs.ParticipanteView>();
        for (Participante_Sorteio__c participante : [
            SELECT Nome__c, Email__c, Ganhador__c, Ordem_Sorteio__c
            FROM Participante_Sorteio__c
            WHERE Sorteio__c = :sorteio.Id
            ORDER BY CreatedDate, Id
            LIMIT :LIMITE_PARTICIPANTES
        ]) {
            painel.participantes.add(criarView(participante, painel.participantes.size() + 1));
        }
        return painel;
    }

    private static SorteioDTOs.ParticipanteView criarView(Participante_Sorteio__c participante, Integer posicao) {
        SorteioDTOs.ParticipanteView view = new SorteioDTOs.ParticipanteView();
        view.posicao = posicao;
        view.nome = participante.Nome__c;
        view.emailMascarado = mascararEmail(participante.Email__c);
        view.ganhador = participante.Ganhador__c;
        view.ordem = participante.Ordem_Sorteio__c == null ? null : participante.Ordem_Sorteio__c.intValue();
        return view;
    }

    private static String mascararEmail(String email) {
        if (String.isBlank(email) || !email.contains('@')) {
            return null;
        }
        return email.left(1) + '***' + email.substring(email.indexOf('@'));
    }

    private static Integer proximaOrdem(Id sorteioId) {
        return [SELECT COUNT() FROM Participante_Sorteio__c WHERE Sorteio__c = :sorteioId AND Ganhador__c = TRUE] + 1;
    }

    private static String tituloOuPadrao(SorteioDTOs.CriarSorteioInput input) {
        String titulo = input == null ? null : PesquisasPortalSecurity.textoSeguro(input.titulo, 80);
        return String.isBlank(titulo) ? TITULO_PADRAO : titulo;
    }

    private static String gerarChaveAleatoria() {
        return EncodingUtil.convertToHex(Crypto.generateAesKey(128));
    }

    private static String gerarHash(String valor) {
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(valor)));
    }

    private static Id resolverProprietario() {
        Id siteId = Site.getSiteId();
        List<Site> sites = siteId == null
            ? new List<Site>()
            : [SELECT GuestRecordDefaultOwnerId FROM Site WHERE Id = :siteId LIMIT 1];
        if (!sites.isEmpty() && sites[0].GuestRecordDefaultOwnerId != null) {
            return sites[0].GuestRecordDefaultOwnerId;
        }
        if (UserInfo.getUserType() != 'Guest') {
            return UserInfo.getUserId();
        }
        throw new PesquisasPortalSecurity.PortalException('Não foi possível iniciar o sorteio. Contate o administrador.');
    }
}