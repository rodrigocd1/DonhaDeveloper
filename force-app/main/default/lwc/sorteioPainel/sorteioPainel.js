import { LightningElement } from "lwc";
import basePath from "@salesforce/community/basePath";
import criarSorteio from "@salesforce/apex/SorteioController.criarSorteio";
import obterPainel from "@salesforce/apex/SorteioController.obterPainel";
import encerrarInscricoes from "@salesforce/apex/SorteioController.encerrarInscricoes";
import sortear from "@salesforce/apex/SorteioController.sortear";
import finalizar from "@salesforce/apex/SorteioController.finalizar";

const CHAVE_SESSAO = "sorteio-operador";
const INTERVALO_ATUALIZACAO_MS = 3000;
const ERRO_PADRAO = "Não foi possível concluir a ação. Tente novamente.";
const STATUS = {
  ABERTO: "Inscricoes_Abertas",
  ENCERRADO: "Inscricoes_Encerradas",
  FINALIZADO: "Finalizado"
};

export default class SorteioPainel extends LightningElement {
  titulo = "";
  operador;
  painel;
  ganhadorAtual;
  resultadoPendente;
  errorMessage;
  isBusy = false;
  isSpinning = false;
  temporizador;

  connectedCallback() {
    this.operador = lerSessao();
    if (this.operador) {
      this.executar(async () => this.aplicarPainel(await obterPainel({ input: this.operador })));
    }
  }

  disconnectedCallback() {
    this.pararAtualizacao();
  }

  get semSorteio() {
    return !this.operador;
  }

  get inscricoesAbertas() {
    return this.painel?.status === STATUS.ABERTO;
  }

  get emSorteio() {
    return this.painel?.status === STATUS.ENCERRADO;
  }

  get finalizado() {
    return this.painel?.status === STATUS.FINALIZADO;
  }

  get tituloExibido() {
    return this.painel?.titulo || "Sorteio";
  }

  get linkParticipacao() {
    return this.operador ? `${window.location.origin}${basePath}/participar?s=${this.operador.chavePublica}` : "";
  }

  get participantes() {
    return this.painel?.participantes ?? [];
  }

  get restantes() {
    return this.participantes.filter((item) => !item.ganhador);
  }

  get ganhadores() {
    return this.participantes.filter((item) => item.ganhador).sort((a, b) => a.ordem - b.ordem);
  }

  get rotuloCadastrados() {
    return `Cadastrados (${this.participantes.length})`;
  }

  get rotuloRestantes() {
    return `Restantes (${this.restantes.length})`;
  }

  get rotuloGanhadores() {
    return `Ganhadores (${this.ganhadores.length})`;
  }

  get rotuloSortear() {
    return `Sortear prêmio ${this.ganhadores.length + 1}`;
  }

  get acaoBloqueada() {
    return this.isBusy || this.isSpinning;
  }

  get sortearBloqueado() {
    return this.acaoBloqueada || this.restantes.length === 0;
  }

  handleTitulo(event) {
    this.titulo = event.target.value;
  }

  handleCriar() {
    this.executar(async () => {
      const criado = await criarSorteio({ input: { titulo: this.titulo } });
      this.operador = { chavePublica: criado.chavePublica, tokenOperador: criado.tokenOperador };
      salvarSessao(this.operador);
      this.aplicarPainel(criado.painel);
    });
  }

  handleEncerrar() {
    this.executar(async () => this.aplicarPainel(await encerrarInscricoes({ input: this.operador })));
  }

  handleFinalizar() {
    this.executar(async () => this.aplicarPainel(await finalizar({ input: this.operador })));
  }

  handleSortear() {
    if (this.sortearBloqueado) {
      return;
    }
    const nomes = this.restantes.map((item) => item.nome);
    this.executar(async () => {
      const resultado = await sortear({ input: this.operador });
      this.ganhadorAtual = undefined;
      this.resultadoPendente = resultado;
      this.isSpinning = true;
      this.template.querySelector("c-sorteio-rolo").girar(nomes, resultado.ganhador.nome);
    });
  }

  handleFimRolo() {
    this.isSpinning = false;
    this.ganhadorAtual = this.resultadoPendente.ganhador;
    this.aplicarPainel(this.resultadoPendente.painel);
    this.resultadoPendente = undefined;
  }

  handleTentarNovamente() {
    this.errorMessage = undefined;
    if (this.operador) {
      this.executar(async () => this.aplicarPainel(await obterPainel({ input: this.operador })));
    }
  }

  handleNovo() {
    this.pararAtualizacao();
    limparSessao();
    this.operador = undefined;
    this.painel = undefined;
    this.ganhadorAtual = undefined;
    this.errorMessage = undefined;
    this.titulo = "";
  }

  async executar(acao) {
    if (this.isBusy) {
      return;
    }
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      await acao();
    } catch (error) {
      this.isSpinning = false;
      this.errorMessage = error?.body?.message || ERRO_PADRAO;
    } finally {
      this.isBusy = false;
    }
  }

  aplicarPainel(painel) {
    this.painel = painel;
    if (painel.status === STATUS.ABERTO) {
      this.iniciarAtualizacao();
    } else {
      this.pararAtualizacao();
    }
  }

  iniciarAtualizacao() {
    if (this.temporizador) {
      return;
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.temporizador = setInterval(() => this.atualizarSilencioso(), INTERVALO_ATUALIZACAO_MS);
  }

  pararAtualizacao() {
    clearInterval(this.temporizador);
    this.temporizador = undefined;
  }

  async atualizarSilencioso() {
    try {
      this.aplicarPainel(await obterPainel({ input: this.operador }));
    } catch (error) {
      this.pararAtualizacao();
      this.errorMessage = error?.body?.message || ERRO_PADRAO;
    }
  }
}

function lerSessao() {
  try {
    const valor = JSON.parse(window.sessionStorage.getItem(CHAVE_SESSAO));
    return valor?.chavePublica && valor?.tokenOperador ? valor : undefined;
  } catch {
    return undefined;
  }
}

function salvarSessao(operador) {
  try {
    window.sessionStorage.setItem(CHAVE_SESSAO, JSON.stringify(operador));
  } catch {
    // Sem sessionStorage o controle permanece apenas enquanto a página estiver aberta.
  }
}

function limparSessao() {
  try {
    window.sessionStorage.removeItem(CHAVE_SESSAO);
  } catch {
    // Nada a limpar quando o navegador bloqueia sessionStorage.
  }
}