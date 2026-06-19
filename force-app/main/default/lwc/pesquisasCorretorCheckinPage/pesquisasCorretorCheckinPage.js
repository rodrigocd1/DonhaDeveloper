import { LightningElement } from "lwc";
import obterLojaPadrao from "@salesforce/apex/PesquisasPortalController.obterLojaPadrao";
import listarLojasAtivas from "@salesforce/apex/PesquisasPortalController.listarLojasAtivas";
import confirmarCheckinCorretor from "@salesforce/apex/PesquisasPortalController.confirmarCheckinCorretor";

export default class PesquisasCorretorCheckinPage extends LightningElement {
  stores = [];
  selectedStoreCode;
  cpf = "";
  honeypot = "";
  storeWarning;
  loadError;
  submitError;
  successMessage;
  isLoading = true;
  isSubmitting = false;
  showSelector = false;

  connectedCallback() {
    this.loadStores();
  }

  async loadStores() {
    this.isLoading = true;
    this.loadError = undefined;
    try {
      const [stores, defaultStore] = await Promise.all([
        listarLojasAtivas(),
        obterLojaPadrao()
      ]);
      this.stores = stores;
      this.selectInitialStore(defaultStore);
    } catch (error) {
      this.loadError =
        error?.body?.message || "Não foi possível carregar as lojas.";
    } finally {
      this.isLoading = false;
    }
  }

  selectInitialStore(defaultStore) {
    const requestedCode = new URL(window.location.href).searchParams.get(
      "loja"
    );
    const requestedStore = this.stores.find(
      (store) => store.codigo === requestedCode
    );
    this.selectedStoreCode = requestedStore?.codigo || defaultStore.codigo;
    this.storeWarning =
      requestedCode && !requestedStore
        ? "A loja informada não foi localizada. Carregamos a loja padrão."
        : undefined;
  }

  get selectedStore() {
    return this.stores.find((store) => store.codigo === this.selectedStoreCode);
  }

  get storeOptions() {
    return this.stores.map((store) => ({
      label: `${store.nome} — ${store.endereco}`,
      value: store.codigo
    }));
  }

  get submitLabel() {
    return this.isSubmitting ? "Confirmando..." : "Confirmar check-in";
  }

  toggleSelector() {
    this.showSelector = !this.showSelector;
  }

  handleStoreChange(event) {
    this.selectedStoreCode = event.detail.value;
    this.storeWarning = undefined;
    this.submitError = undefined;
    this.successMessage = undefined;
    this.updateUrl();
  }

  handleCpfChange(event) {
    const digits = event.detail.value.replace(/\D/g, "").slice(0, 11);
    this.cpf = this.formatCpf(digits);
    this.submitError = undefined;
    this.successMessage = undefined;
  }

  handleHoneypotChange(event) {
    this.honeypot = event.target.value;
  }

  async handleSubmit(event) {
    event.preventDefault();
    const input = this.template.querySelector(".cpf-input");
    const digits = this.cpf.replace(/\D/g, "");
    input.setCustomValidity(
      digits.length === 11 ? "" : "Informe um CPF com 11 dígitos."
    );
    if (this.isSubmitting || !input.reportValidity()) {
      return;
    }
    await this.confirmCheckin();
  }

  async confirmCheckin() {
    this.isSubmitting = true;
    this.submitError = undefined;
    this.successMessage = undefined;
    try {
      const result = await confirmarCheckinCorretor({
        input: {
          cpf: this.cpf,
          codigoLoja: this.selectedStoreCode,
          honeypot: this.honeypot
        }
      });
      this.successMessage = result.mensagem;
      this.cpf = "";
    } catch (error) {
      this.submitError =
        error?.body?.message || "Não foi possível confirmar o check-in agora.";
    } finally {
      this.isSubmitting = false;
    }
  }

  updateUrl() {
    const url = new URL(window.location.href);
    url.searchParams.set("loja", this.selectedStoreCode);
    window.history.replaceState({}, "", `${url.pathname}${url.search}`);
  }

  formatCpf(digits) {
    return digits
      .replace(/^(\d{3})(\d)/, "$1.$2")
      .replace(/^(\d{3})\.(\d{3})(\d)/, "$1.$2.$3")
      .replace(/\.(\d{3})(\d)/, ".$1-$2");
  }
}
