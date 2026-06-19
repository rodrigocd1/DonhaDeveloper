import { LightningElement } from "lwc";

export default class PesquisasHome extends LightningElement {
  handleSelect(event) {
    this.dispatchEvent(
      new CustomEvent("selecionar", {
        detail: event.currentTarget.dataset.journey
      })
    );
  }
}
