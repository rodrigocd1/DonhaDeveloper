import { LightningElement, api } from "lwc";
import consultarRecepcao from "@salesforce/apex/PesquisasPortalController.consultarRecepcao";
import registrarCheckin from "@salesforce/apex/PesquisasPortalController.registrarCheckin";
import criarLeadRapidoECheckin from "@salesforce/apex/PesquisasPortalController.criarLeadRapidoECheckin";

export default class PesquisasRecepcao extends LightningElement {
  @api empreendimentoOptions = [];
  empreendimentoId;
  identificacao;
  nomeCompleto;
  status;
  errorMessage;
  isSubmitting = false;

  get comboboxOptions() {
    return this.empreendimentoOptions.map((item) => ({
      label: [item.nome, item.bairro, item.regiao].filter(Boolean).join(" — "),
      value: item.id
    }));
  }

  get showSearch() {
    return !this.status;
  }

  get showFound() {
    return this.status === "ENCONTRADO";
  }

  get showNotFound() {
    return this.status === "NAO_ENCONTRADO";
  }

  get showAmbiguous() {
    return this.status === "AMBIGUO";
  }

  get hasResult() {
    return Boolean(this.status);
  }

  get searchLabel() {
    return this.isSubmitting ? "Consultando..." : "Consultar cadastro";
  }

  get confirmLabel() {
    return this.isSubmitting ? "Registrando..." : "Confirmar check-in";
  }

  get quickLabel() {
    return this.isSubmitting ? "Registrando..." : "Cadastrar e fazer check-in";
  }

  handleEmpreendimento(event) {
    this.empreendimentoId = event.detail.value;
    this.errorMessage = undefined;
  }

  handleName(event) {
    this.nomeCompleto = event.detail.value;
    this.errorMessage = undefined;
  }

  async handleSearch(event) {
    event.preventDefault();
    const identityComponent = this.template.querySelector(
      "c-pesquisas-identificacao"
    );
    const empreendimento = this.template.querySelector("lightning-combobox");
    if (
      this.isSubmitting ||
      !identityComponent.reportValidity() ||
      !empreendimento.reportValidity()
    ) {
      return;
    }
    this.identificacao = {
      ...identityComponent.getValue(),
      empreendimentoId: this.empreendimentoId
    };
    await this.execute(async () => {
      const result = await consultarRecepcao({ input: this.identificacao });
      this.status = result.status;
    });
  }

  async handleCheckin() {
    await this.execute(async () => {
      const result = await registrarCheckin({ input: this.identificacao });
      this.dispatchEvent(
        new CustomEvent("sucesso", { detail: result.mensagem })
      );
    });
  }

  async handleQuickCheckin() {
    const nameInput = this.template.querySelector(
      '[data-field="nomeCompleto"]'
    );
    if (!nameInput.reportValidity()) {
      return;
    }
    await this.execute(async () => {
      const result = await criarLeadRapidoECheckin({
        input: { ...this.identificacao, nomeCompleto: this.nomeCompleto }
      });
      this.dispatchEvent(
        new CustomEvent("sucesso", { detail: result.mensagem })
      );
    });
  }

  async execute(action) {
    if (this.isSubmitting) {
      return;
    }
    this.isSubmitting = true;
    this.errorMessage = undefined;
    try {
      await action();
    } catch (error) {
      this.errorMessage =
        error?.body?.message || "Não foi possível concluir a solicitação.";
    } finally {
      this.isSubmitting = false;
    }
  }

  resetSearch() {
    this.status = undefined;
    this.identificacao = undefined;
    this.nomeCompleto = undefined;
    this.errorMessage = undefined;
  }

  handleBack() {
    this.dispatchEvent(new CustomEvent("voltar"));
  }
}
