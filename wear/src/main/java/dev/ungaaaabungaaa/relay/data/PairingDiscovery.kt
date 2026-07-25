package dev.ungaaaabungaaa.relay.data

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo

class PairingDiscovery(context: Context) {
    private val manager = context.getSystemService(NsdManager::class.java)
    private var listener: NsdManager.DiscoveryListener? = null

    fun start(
        onDiscovered: (PairingDiscoveryRecord) -> Unit,
        onError: (String) -> Unit,
    ) {
        if (listener != null) return
        val discoveryListener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) = Unit

            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                if (serviceInfo.serviceType != SERVICE_TYPE) return
                @Suppress("DEPRECATION")
                manager.resolveService(
                    serviceInfo,
                    object : NsdManager.ResolveListener {
                        override fun onResolveFailed(
                            serviceInfo: NsdServiceInfo,
                            errorCode: Int,
                        ) = Unit

                        override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                            PairingDiscoveryRecord.fromTxtAttributes(serviceInfo.attributes)
                                ?.let(onDiscovered)
                        }
                    },
                )
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo) = Unit

            override fun onDiscoveryStopped(serviceType: String) = Unit

            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                stop()
                onError("Same-Wi-Fi discovery could not start")
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                listener = null
            }
        }
        listener = discoveryListener
        manager.discoverServices(
            SERVICE_TYPE,
            NsdManager.PROTOCOL_DNS_SD,
            discoveryListener,
        )
    }

    fun stop() {
        val active = listener ?: return
        listener = null
        runCatching { manager.stopServiceDiscovery(active) }
    }

    companion object {
        private const val SERVICE_TYPE = "_relay-pair._tcp."
    }
}
