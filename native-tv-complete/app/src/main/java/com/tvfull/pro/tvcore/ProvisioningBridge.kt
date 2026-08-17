package com.tvfull.pro.tvcore

import android.content.Context
import com.tvfull.pro.RemoteConfigResult
import com.tvfull.pro.RemoteConfigState
import com.tvfull.pro.RemotePrefs
import com.tvfull.pro.RemoteProvisioningClient

class ProvisioningBridge(private val context: Context) {
    fun fetch(): Pair<RemoteConfigResult, List<ProvisionedSource>> {
        val credentials = RemotePrefs.loadCredentials(context)
            ?: return RemoteConfigResult(RemoteConfigState.INVALID, message = "Dispositivo sin vincular") to emptyList()

        val result = RemoteProvisioningClient.fetchConfig(credentials)
        if (result.state != RemoteConfigState.READY) return result to emptyList()

        val sources = result.services.map {
            ProvisionedSource(
                serviceId = it.id,
                serviceName = it.name,
                config = it.config,
                expiresAt = it.expiresAt
            )
        }
        return result to sources
    }
}
