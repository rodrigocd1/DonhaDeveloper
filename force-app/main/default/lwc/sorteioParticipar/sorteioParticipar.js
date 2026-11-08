import { LightningElement } from "lwc";
import consultarSorteio from "@salesforce/apex/SorteioController.consultarSorteio";
import inscrever from "@salesforce/apex/SorteioController.inscrever";

const ERRO_PADRAO = "Não foi possível concluir a inscrição. Tente novamente.";
const CAMPOS = ["nome", "email", "codigo", "honeypot"];

export default class SorteioParticipar extends LightningElement {
  chavePublica;
  titulo;
  inscricoesAbertas = false;
  isLoading = true;
  isSubmitting = false;
  loadError;
  errorMessage;
  successMessage;
  nome = "";
  email = "";
  codigo = "";
  honeypot = "";
  padraoCodigo = "[0-9]{4}";

  connectedCallback() {
    this.chavePublica = new URLSearchParams(window.location.search).get("s");
    this.carregar();
  }

  get tituloExibido() {
    return this.titulo || "Sorteio";
  }

  get rotuloEnviar() {
    return this.isSubmitting ? "Enviando..." : "Quero participar";
  }

  async carregar() {
    if (!this.chavePublica) {
      this.finalizarCarga("Link do sorteio inválido.");
      return;
    }
    try {
      const info = await consultarSorteio({ chavePublica: this.chavePublica });
      this.titulo = info.titulo;
      this.inscricoesAbertas = info.inscricoesAbertas;
      this.finalizarCarga();
    } catch (error) {
      this.finalizarCarga(error?.body?.message || ERRO_PADRAO);
    }
  }

  finalizarCarga(mensagem) {
    this.loadError = mensagem;
    this.isLoading = false;
  }

  handleChange(event) {
    const campo = event.target.dataset.field;
    if (CAMPOS.includes(campo)) {
      this[campo] = event.target.value;
    }
  }

  async handleSubmit() {
    if (this.isSubmitting || !this.formularioValido()) {
      return;
    }
    this.isSubmitting = true;
    this.errorMessage = undefined;
    try {
      const resultado = await inscrever({ input: this.montarInscricao() });
      this.successMessage = resultado.mensagem;
    } catch (error) {
      this.errorMessage = error?.body?.message || ERRO_PADRAO;
    } finally {
      this.isSubmitting = false;
    }
  }

  montarInscricao() {
    return {
      chavePublica: this.chavePublica,
      nome: this.nome,
      email: this.email,
      codigoAcesso: this.codigo,
      honeypot: this.honeypot
    };
  }

  formularioValido() {
    return [...this.template.querySelectorAll("lightning-input")].reduce(
      (valido, campo) => campo.reportValidity() && valido,
      true
    );
  }
}