import { LightningElement, api } from "lwc";

const ALTURA_ITEM_REM = 5;
const ITENS_ANTES_DO_GANHADOR = 40;
const DURACAO_MS = 6000;
const DURACAO_REDUZIDA_MS = 400;
const QUANTIDADE_CONFETE = 40;
const CORES_CONFETE = ["#f6b51b", "#ffffff", "#e4572e", "#2bb673", "#4aa3ff"];

export default class SorteioRolo extends LightningElement {
  itens = [];
  confetes = [];
  estiloRolo = "";
  ganhador;
  parado = true;

  @api
  girar(nomes, ganhador) {
    this.ganhador = ganhador;
    this.confetes = [];
    this.parado = false;
    this.itens = montarItens(nomes, ganhador);
    this.estiloRolo = "transform: translateY(0); transition: none;";
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    requestAnimationFrame(() => {
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      requestAnimationFrame(() => {
        this.estiloRolo = estiloFinal();
      });
    });
  }

  get classeJanela() {
    return this.parado && this.ganhador ? "janela janela_revelada" : "janela";
  }

  handleTransitionEnd() {
    if (this.parado) {
      return;
    }
    this.parado = true;
    this.confetes = movimentoReduzido() ? [] : gerarConfetes();
    this.dispatchEvent(new CustomEvent("fim", { detail: { ganhador: this.ganhador } }));
  }
}

function montarItens(nomes, ganhador) {
  const base = nomes && nomes.length ? embaralhar(nomes) : [ganhador];
  const itens = [];
  for (let indice = 0; indice < ITENS_ANTES_DO_GANHADOR; indice++) {
    itens.push({ chave: `n${indice}`, nome: base[indice % base.length] });
  }
  itens.push({ chave: "ganhador", nome: ganhador });
  itens.push({ chave: "depois", nome: base[ITENS_ANTES_DO_GANHADOR % base.length] });
  return itens;
}

function embaralhar(lista) {
  const copia = [...lista];
  for (let indice = copia.length - 1; indice > 0; indice--) {
    const sorteado = Math.floor(Math.random() * (indice + 1));
    [copia[indice], copia[sorteado]] = [copia[sorteado], copia[indice]];
  }
  return copia;
}

function movimentoReduzido() {
  return window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches === true;
}

function estiloFinal() {
  const duracao = movimentoReduzido() ? DURACAO_REDUZIDA_MS : DURACAO_MS;
  const deslocamento = ITENS_ANTES_DO_GANHADOR * ALTURA_ITEM_REM;
  return `transform: translateY(-${deslocamento}rem); transition: transform ${duracao}ms cubic-bezier(0.12, 0.8, 0.2, 1);`;
}

function gerarConfetes() {
  return Array.from({ length: QUANTIDADE_CONFETE }, (_, indice) => ({
    chave: `c${indice}`,
    estilo: `left: ${Math.random() * 100}%; background: ${CORES_CONFETE[indice % CORES_CONFETE.length]}; animation-delay: ${Math.random() * 0.6}s;`
  }));
}