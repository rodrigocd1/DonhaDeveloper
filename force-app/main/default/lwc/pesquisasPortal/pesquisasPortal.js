import { LightningElement } from "lwc";
import listarEmpreendimentos from "@salesforce/apex/PesquisasPortalController.listarEmpreendimentos";

export default class PesquisasPortal extends LightningElement {
  empreendimentoOptions = [];
  selectedJourney;
  errorMessage;
  successMessage;
  isLoading = true;

  connectedCallback() {
    this.loadEmpreendimentos();
  }

  async loadEmpreendimentos() {
    this.isLoading = true;
    this.errorMessage = undefined;
    try {
      this.empreendimentoOptions = await listarEmpreendimentos();
    } catch (error) {
      this.errorMessage = this.getErrorMessage(error);
    } finally {
      this.isLoading = false;
    }
  }

  handleSelect(event) {
    this.successMessage = undefined;
    this.selectedJourney = event.detail;
  }

  handleBack() {
    this.selectedJourney = undefined;
    this.successMessage = undefined;
  }

  handleSuccess(event) {
    this.selectedJourney = undefined;
    this.successMessage = event.detail;
  }

  get showHome() {
    return !this.selectedJourney && !this.successMessage;
  }

  get showAgendamento() {
    return this.selectedJourney === "agendamento";
  }

  get showRecepcao() {
    return this.selectedJourney === "recepcao";
  }

  get showAvaliacao() {
    return this.selectedJourney === "avaliacao";
  }

  getErrorMessage(error) {
    return (
      error?.body?.message ||
      "Não foi possível carregar as opções. Tente novamente."
    );
  }
}
